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

nonisolated struct HAHistorySample: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

private nonisolated struct HAHistoryState: Decodable, Sendable {
    let entityID: String
    let state: String
    let lastChanged: String?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
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

    func fetchHistory(entityID: String, hours: Int) async throws -> [HAHistorySample] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-Double(max(hours, 1)) * 3600)
        let formatter = Self.historyDateFormatter
        let encodedStart = formatter.string(from: startDate).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)

        guard let encodedStart else {
            throw HomeAssistantClientError.invalidURL
        }

        var components = URLComponents(url: absoluteURL(for: "/api/history/period/\(encodedStart)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "filter_entity_id", value: entityID),
            URLQueryItem(name: "end_time", value: formatter.string(from: endDate)),
            URLQueryItem(name: "minimal_response", value: "1"),
            URLQueryItem(name: "significant_changes_only", value: "0")
        ]

        guard let url = components?.url else {
            throw HomeAssistantClientError.invalidURL
        }

        let data = try await requestData(at: url)
        let rawHistory = try JSONDecoder().decode([[HAHistoryState]].self, from: data)

        return rawHistory
            .flatMap { $0 }
            .compactMap { state in
                guard let value = Double(state.state),
                      let timestamp = Self.parseHistoryDate(state.lastChanged ?? state.lastUpdated) else {
                    return nil
                }

                return HAHistorySample(timestamp: timestamp, value: value)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func fetchEnergyPreferences() async throws -> HAEnergyPreferences {
        let result = try await callWebSocket(type: "energy/get_prefs")
        return try decode(HAEnergyPreferences.self, from: result)
    }

    func fetchStatistics(
        statisticID: String,
        hours: Int,
        period: HAStatisticsPeriod = .hour
    ) async throws -> [HAHistorySample] {
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-Double(max(hours, 1)) * 3600)
        let formatter = Self.historyDateFormatter

        let result = try await callWebSocket(
            type: "recorder/statistics_during_period",
            payload: [
                "start_time": .string(formatter.string(from: startDate)),
                "end_time": .string(formatter.string(from: endDate)),
                "statistic_ids": .array([.string(statisticID)]),
                "period": .string(period.rawValue)
            ]
        )

        let series = try decode([String: [HAStatisticBucket]].self, from: result)
        let buckets = series[statisticID] ?? []

        return buckets.compactMap { bucket in
            guard let value = bucket.representativeValue else {
                return nil
            }

            return HAHistorySample(timestamp: bucket.start, value: value)
        }
    }

    func fetchWeatherForecast(
        entityID: String,
        type: HAWeatherForecastType = .daily
    ) async throws -> [HAWeatherForecastEntry] {
        let body = try JSONEncoder().encode([
            "entity_id": entityID,
            "type": type.rawValue
        ])
        let url = absoluteURL(for: "/api/services/weather/get_forecasts?return_response")
        let data = try await requestData(at: url, method: "POST", body: body)
        let response = try JSONDecoder().decode(HAWeatherForecastResponse.self, from: data)
        return response.serviceResponse[entityID]?.forecast ?? []
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
        return absoluteURL(for: stream.url)
    }

    func absoluteURL(for path: String) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }

        if let resolved = URL(string: path, relativeTo: relativeResolutionBaseURL())?.absoluteURL {
            return resolved
        }

        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appending(path: trimmedPath)
    }

    private func request<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let targetURL = absoluteURL(for: path)
        let data = try await requestData(at: targetURL)
        return try JSONDecoder().decode(type, from: data)
    }

    private func requestData(
        at targetURL: URL,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        var request = URLRequest(url: targetURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw HomeAssistantClientError.invalidResponse
        }

        return data
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

    private func relativeResolutionBaseURL() -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        if components.path.isEmpty {
            components.path = "/"
        } else if !components.path.hasSuffix("/") {
            components.path += "/"
        }

        return components.url ?? baseURL
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
                    self.resumePendingCall(messageID, with: error)
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

    private static let historyDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let historyFallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseHistoryDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return historyDateFormatter.date(from: value)
            ?? historyFallbackDateFormatter.date(from: value)
    }
}

nonisolated private struct SignedPath: Codable {
    let path: String
}

nonisolated private struct HAStreamResponse: Codable {
    let url: String
}
