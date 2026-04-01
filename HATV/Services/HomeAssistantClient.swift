import Foundation

enum HomeAssistantClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationFailed
    case websocketClosed
    case missingSocket
    case remote(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Home Assistant URL is invalid."
        case .invalidResponse:
            return "Home Assistant returned a response the app could not read."
        case .authenticationFailed:
            return "Home Assistant rejected the access token."
        case .websocketClosed:
            return "The Home Assistant live connection closed unexpectedly."
        case .missingSocket:
            return "The Home Assistant live connection is not ready yet."
        case .remote(let message):
            return message
        }
    }
}

nonisolated struct HAInstanceInfo: Codable, Sendable {
    let version: String
    let locationName: String
    let language: String
    let timeZone: String

    enum CodingKeys: String, CodingKey {
        case version
        case locationName = "location_name"
        case language
        case timeZone = "time_zone"
    }
}

actor HomeAssistantClient {
    private let baseURL: URL
    private let token: String
    private let urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var nextMessageID = 1
    private var pendingCalls: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var eventHandlers: [Int: @Sendable (JSONDictionary) async -> Void] = [:]

    init(baseURL: URL, token: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.urlSession = urlSession
    }

    func validateConnection() async throws -> HAInstanceInfo {
        try await request("/api/config", as: HAInstanceInfo.self)
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failAllPendingCalls(with: HomeAssistantClientError.websocketClosed)
        eventHandlers.removeAll()
    }

    func fetchDashboards() async throws -> [HADashboardSummary] {
        let result = try await callWebSocket(type: "lovelace/dashboards/list")
        return try decode([HADashboardSummary].self, from: result)
    }

    func fetchDashboardConfig(urlPath: String?) async throws -> HALovelaceConfig {
        var message: JSONDictionary = [
            "force": .bool(false)
        ]

        if let urlPath, !urlPath.isEmpty {
            message["url_path"] = .string(urlPath)
        } else {
            message["url_path"] = .null
        }

        let result = try await callWebSocket(type: "lovelace/config", payload: message)
        return try decode(HALovelaceConfig.self, from: result)
    }

    func fetchStates() async throws -> [HAEntityState] {
        let result = try await callWebSocket(type: "get_states")
        return try decode([HAEntityState].self, from: result)
    }

    func subscribe(
        eventType: String,
        handler: @escaping @Sendable (JSONDictionary) async -> Void
    ) async throws -> Int {
        try await ensureConnected()

        let messageID = nextID()
        eventHandlers[messageID] = handler

        do {
            _ = try await sendMessage(
                [
                    "type": .string("subscribe_events"),
                    "event_type": .string(eventType)
                ],
                forcedID: messageID
            )
            return messageID
        } catch {
            eventHandlers.removeValue(forKey: messageID)
            throw error
        }
    }

    func callService(
        named serviceName: String,
        targetEntityIDs: [String] = [],
        serviceData: JSONDictionary = [:]
    ) async throws {
        let parts = serviceName.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw HomeAssistantClientError.remote(message: "Unknown service \(serviceName).")
        }

        var payload: JSONDictionary = [
            "domain": .string(parts[0]),
            "service": .string(parts[1])
        ]

        if !targetEntityIDs.isEmpty {
            payload["target"] = .object([
                "entity_id": .array(targetEntityIDs.map(JSONValue.string))
            ])
        }

        if !serviceData.isEmpty {
            payload["service_data"] = .object(serviceData)
        }

        _ = try await callWebSocket(type: "call_service", payload: payload)
    }

    func signedPath(for path: String, expires: Int = 43_200) async throws -> URL {
        let result = try await callWebSocket(
            type: "auth/sign_path",
            payload: [
                "path": .string(path),
                "expires": .number(Double(expires))
            ]
        )
        let signedPath = try decode(SignedPath.self, from: result)
        return absoluteURL(for: signedPath.path)
    }

    func signedCameraPreviewURL(entityID: String) async throws -> URL {
        try await signedPath(for: "/api/camera_proxy/\(entityID)")
    }

    func signedCameraStreamURL(entityID: String) async throws -> URL {
        let result = try await callWebSocket(
            type: "camera/stream",
            payload: [
                "entity_id": .string(entityID),
                "format": .string("hls")
            ]
        )
        let stream = try decode(HAStreamResponse.self, from: result)
        return try await signedPath(for: stream.url)
    }

    func absoluteURL(for path: String) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }

        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appending(path: trimmedPath)
    }

    private func request<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let targetURL = absoluteURL(for: path)
        var request = URLRequest(url: targetURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw HomeAssistantClientError.invalidResponse
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func ensureConnected() async throws {
        if webSocketTask != nil {
            return
        }

        guard let socketURL = websocketURL() else {
            throw HomeAssistantClientError.invalidURL
        }

        let task = urlSession.webSocketTask(with: socketURL)
        task.resume()

        let authRequired = try await receiveMessage(from: task)
        guard authRequired["type"]?.stringValue == "auth_required" else {
            throw HomeAssistantClientError.invalidResponse
        }

        try await sendRaw(
            [
                "type": .string("auth"),
                "access_token": .string(token)
            ],
            over: task
        )

        let authReply = try await receiveMessage(from: task)
        switch authReply["type"]?.stringValue {
        case "auth_ok":
            webSocketTask = task
            receiveLoopTask = Task { await receiveLoop(task: task) }
        case "auth_invalid":
            task.cancel(with: .policyViolation, reason: nil)
            throw HomeAssistantClientError.authenticationFailed
        default:
            task.cancel(with: .protocolError, reason: nil)
            throw HomeAssistantClientError.invalidResponse
        }
    }

    private func websocketURL() -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let currentPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = currentPath.isEmpty ? "/api/websocket" : "/\(currentPath)/api/websocket"
        return components.url
    }

    private func callWebSocket(type: String, payload: JSONDictionary = [:]) async throws -> JSONValue {
        try await ensureConnected()

        var message = payload
        message["type"] = .string(type)
        return try await sendMessage(message)
    }

    private func sendMessage(_ message: JSONDictionary, forcedID: Int? = nil) async throws -> JSONValue {
        let messageID = forcedID ?? nextID()

        return try await withCheckedThrowingContinuation { continuation in
            pendingCalls[messageID] = continuation

            Task {
                do {
                    try await self.sendRaw(
                        message.merging(["id": .number(Double(messageID))], uniquingKeysWith: { _, new in new })
                    )
                } catch {
                    await self.resumePendingCall(messageID, with: error)
                }
            }
        }
    }

    private func nextID() -> Int {
        defer { nextMessageID += 1 }
        return nextMessageID
    }

    private func sendRaw(_ message: JSONDictionary) async throws {
        guard let task = webSocketTask else {
            throw HomeAssistantClientError.missingSocket
        }
        try await sendRaw(message, over: task)
    }

    private func sendRaw(_ message: JSONDictionary, over task: URLSessionWebSocketTask) async throws {
        let data = try JSONEncoder().encode(message)
        guard let string = String(data: data, encoding: .utf8) else {
            throw HomeAssistantClientError.invalidResponse
        }
        try await task.send(.string(string))
    }

    private func receiveMessage(from task: URLSessionWebSocketTask) async throws -> JSONDictionary {
        let message = try await task.receive()
        let data: Data

        switch message {
        case .string(let string):
            guard let stringData = string.data(using: .utf8) else {
                throw HomeAssistantClientError.invalidResponse
            }
            data = stringData
        case .data(let binaryData):
            data = binaryData
        @unknown default:
            throw HomeAssistantClientError.invalidResponse
        }

        return try JSONDecoder().decode(JSONDictionary.self, from: data)
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await receiveMessage(from: task)
                await handleIncoming(message)
            } catch {
                break
            }
        }

        webSocketTask = nil
        receiveLoopTask = nil
        failAllPendingCalls(with: HomeAssistantClientError.websocketClosed)
    }

    private func handleIncoming(_ message: JSONDictionary) async {
        let type = message["type"]?.stringValue
        let id = message["id"]?.intValue

        switch type {
        case "result":
            guard let id else { return }
            if message["success"]?.boolValue == true {
                let result = message["result"] ?? .null
                resumePendingCall(id, with: result)
            } else {
                let errorMessage = message["error"]?.objectValue?["message"]?.stringValue
                    ?? "Home Assistant returned an error."
                resumePendingCall(id, with: HomeAssistantClientError.remote(message: errorMessage))
            }
        case "event":
            guard let id, let handler = eventHandlers[id] else { return }
            Task {
                await handler(message)
            }
        default:
            break
        }
    }

    private func resumePendingCall(_ id: Int, with result: JSONValue) {
        let continuation = pendingCalls.removeValue(forKey: id)
        continuation?.resume(returning: result)
    }

    private func resumePendingCall(_ id: Int, with error: Error) {
        let continuation = pendingCalls.removeValue(forKey: id)
        continuation?.resume(throwing: error)
    }

    private func failAllPendingCalls(with error: Error) {
        let pending = pendingCalls
        pendingCalls.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from result: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(type, from: data)
    }
}

nonisolated private struct SignedPath: Codable {
    let path: String
}

nonisolated private struct HAStreamResponse: Codable {
    let url: String
}
