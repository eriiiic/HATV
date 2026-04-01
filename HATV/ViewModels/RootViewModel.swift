import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class RootViewModel {
    enum Screen {
        case booting
        case connection
        case dashboardPicker
        case dashboard
    }

    var screen: Screen = .booting
    var connectionName = "Home Assistant"
    var serverURLString = ""
    var accessToken = ""
    var instanceInfo: HAInstanceInfo?
    var dashboards: [HADashboardSummary] = []
    var selectedDashboard: HADashboardSummary?
    var dashboardConfig: HALovelaceConfig?
    var selectedViewIndex = 0
    var entityStates: [String: HAEntityState] = [:]
    var cameraPreviewURLs: [String: URL] = [:]
    var cameraStreamURLs: [String: URL] = [:]
    var isBusy = false
    var statusMessage = "Loading…"
    var errorMessage: String?

    private(set) var didBootstrap = false
    private let tokenStore = KeychainTokenStore()
    private var client: HomeAssistantClient?
    private var stateSubscriptionID: Int?
    private var lovelaceSubscriptionID: Int?

    var currentView: HALovelaceView? {
        guard let dashboardConfig, dashboardConfig.views.indices.contains(selectedViewIndex) else {
            return dashboardConfig?.views.first
        }
        return dashboardConfig.views[selectedViewIndex]
    }

    func bootstrap(with storedConnection: StoredConnection?) async {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard let storedConnection else {
            screen = .connection
            return
        }

        connectionName = storedConnection.name
        serverURLString = storedConnection.baseURLString

        do {
            guard let token = try tokenStore.load(account: storedConnection.id), !token.isEmpty else {
                screen = .connection
                return
            }

            accessToken = token
            try await connectSession(
                name: storedConnection.name,
                baseURLString: storedConnection.baseURLString,
                token: token,
                storedConnection: storedConnection,
                autoLaunchSelection: storedConnection.autoLaunchDashboard
            )
        } catch {
            screen = .connection
            errorMessage = error.localizedDescription
        }
    }

    func connect(modelContext: ModelContext, storedConnection: StoredConnection?) async {
        errorMessage = nil

        let trimmedName = connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty, !trimmedToken.isEmpty else {
            errorMessage = "Enter a Home Assistant URL and long-lived access token."
            screen = .connection
            return
        }

        do {
            let persisted = upsertConnection(
                named: trimmedName.isEmpty ? "Home Assistant" : trimmedName,
                baseURLString: trimmedURL,
                in: modelContext,
                existing: storedConnection
            )
            try tokenStore.save(trimmedToken, account: persisted.id)
            accessToken = trimmedToken

            try await connectSession(
                name: persisted.name,
                baseURLString: persisted.baseURLString,
                token: trimmedToken,
                storedConnection: persisted,
                autoLaunchSelection: persisted.autoLaunchDashboard
            )
        } catch {
            errorMessage = error.localizedDescription
            screen = .connection
        }
    }

    func chooseDashboard(
        _ dashboard: HADashboardSummary,
        storedConnection: StoredConnection?,
        modelContext: ModelContext
    ) async {
        selectedDashboard = dashboard

        if let storedConnection {
            storedConnection.selectedDashboardID = dashboard.id
            storedConnection.selectedDashboardURLPath = dashboard.normalizedURLPath
            storedConnection.selectedDashboardTitle = dashboard.title
            storedConnection.updatedAt = .now
            try? modelContext.save()
        }

        await reloadSelectedDashboard()
    }

    func reloadSelectedDashboard() async {
        guard let selectedDashboard, let client else { return }

        isBusy = true
        statusMessage = "Loading \(selectedDashboard.title)…"

        defer { isBusy = false }

        do {
            dashboardConfig = try await client.fetchDashboardConfig(urlPath: selectedDashboard.normalizedURLPath)
            selectedViewIndex = 0
            screen = .dashboard
            await preloadCameraURLs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showDashboardPicker() {
        screen = .dashboardPicker
    }

    func showConnectionEditor() {
        screen = .connection
    }

    func selectView(_ view: HALovelaceView) {
        guard let dashboardConfig else { return }
        if let index = dashboardConfig.views.firstIndex(where: { $0.id == view.id }) {
            selectedViewIndex = index
        }
    }

    func state(for entityID: String?) -> HAEntityState? {
        guard let entityID else { return nil }
        return entityStates[entityID]
    }

    func cameraPreviewURL(for entityID: String) -> URL? {
        cameraPreviewURLs[entityID]
    }

    func cameraStreamURL(for entityID: String) -> URL? {
        cameraStreamURLs[entityID]
    }

    func executePrimaryAction(for card: HAAnyConfig) async {
        await executeAction(card.tapAction, fallbackEntityID: card.entityID)
    }

    func executePrimaryAction(for item: HAEntityItem) async {
        await executeAction(item.action, fallbackEntityID: item.entityID)
    }

    private func executeAction(_ action: HAActionConfig?, fallbackEntityID: String?) async {
        guard let client else { return }

        do {
            if let action {
                switch action.kind {
                case "navigate":
                    if let navigationPath = action.navigationPath {
                        navigate(to: navigationPath)
                    }
                case "call-service", "perform-action":
                    if let serviceName = action.serviceName {
                        let targetIDs = action.targetEntityIDs.isEmpty
                            ? [fallbackEntityID].compactMap { $0 }
                            : action.targetEntityIDs
                        try await client.callService(
                            named: serviceName,
                            targetEntityIDs: targetIDs,
                            serviceData: action.serviceData
                        )
                    }
                case "toggle":
                    if let fallbackEntityID {
                        try await client.callService(named: "homeassistant.toggle", targetEntityIDs: [fallbackEntityID])
                    }
                default:
                    if let fallbackEntityID {
                        try await performDefaultAction(for: fallbackEntityID)
                    }
                }
            } else if let fallbackEntityID {
                try await performDefaultAction(for: fallbackEntityID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performDefaultAction(for entityID: String) async throws {
        guard let client, let state = entityStates[entityID] else {
            return
        }

        switch state.domain {
        case "button", "input_button":
            try await client.callService(named: "\(state.domain).press", targetEntityIDs: [entityID])
        case "scene", "script":
            try await client.callService(named: "homeassistant.turn_on", targetEntityIDs: [entityID])
        case "cover":
            let serviceName = state.state.lowercased() == "open" ? "cover.close_cover" : "cover.open_cover"
            try await client.callService(named: serviceName, targetEntityIDs: [entityID])
        case "lock":
            let serviceName = state.state.lowercased() == "locked" ? "lock.unlock" : "lock.lock"
            try await client.callService(named: serviceName, targetEntityIDs: [entityID])
        default:
            if state.isToggleLike {
                try await client.callService(named: "homeassistant.toggle", targetEntityIDs: [entityID])
            }
        }
    }

    private func navigate(to path: String) {
        let candidate = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last
            .map(String.init) ?? path

        guard let dashboardConfig,
              let index = dashboardConfig.views.firstIndex(where: { $0.matchesNavigationPath(candidate) }) else {
            return
        }

        selectedViewIndex = index
    }

    private func connectSession(
        name: String,
        baseURLString: String,
        token: String,
        storedConnection: StoredConnection?,
        autoLaunchSelection: Bool
    ) async throws {
        isBusy = true
        statusMessage = "Connecting to \(name)…"
        defer { isBusy = false }

        await client?.disconnect()

        guard let url = normalizedURL(from: baseURLString) else {
            throw HomeAssistantClientError.invalidURL
        }

        stateSubscriptionID = nil
        lovelaceSubscriptionID = nil

        let nextClient = HomeAssistantClient(baseURL: url, token: token)
        let info = try await nextClient.validateConnection()
        let dashboards = try await nextClient.fetchDashboards()
        let states = try await nextClient.fetchStates()

        client = nextClient
        connectionName = name
        serverURLString = baseURLString
        instanceInfo = info
        entityStates = Dictionary(uniqueKeysWithValues: states.map { ($0.entityID, $0) })
        self.dashboards = dashboards.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        try await beginSubscriptions(with: nextClient)

        if autoLaunchSelection,
           let storedConnection,
           let dashboard = matchingDashboard(for: storedConnection, dashboards: dashboards) {
            selectedDashboard = dashboard
            await reloadSelectedDashboard()
        } else {
            screen = dashboards.isEmpty ? .connection : .dashboardPicker
            if dashboards.isEmpty {
                errorMessage = "No Lovelace dashboards are available for this account."
            }
        }
    }

    private func upsertConnection(
        named name: String,
        baseURLString: String,
        in modelContext: ModelContext,
        existing: StoredConnection?
    ) -> StoredConnection {
        let connection = existing ?? StoredConnection()
        connection.name = name
        connection.baseURLString = baseURLString
        connection.updatedAt = .now

        if existing == nil {
            modelContext.insert(connection)
        }

        try? modelContext.save()
        return connection
    }

    private func matchingDashboard(
        for connection: StoredConnection,
        dashboards: [HADashboardSummary]
    ) -> HADashboardSummary? {
        dashboards.first {
            $0.id == connection.selectedDashboardID
                || $0.normalizedURLPath == connection.selectedDashboardURLPath
        }
    }

    private func normalizedURL(from string: String) -> URL? {
        var candidate = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        return URL(string: candidate)
    }

    private func beginSubscriptions(with client: HomeAssistantClient) async throws {
        if stateSubscriptionID == nil {
            stateSubscriptionID = try await client.subscribe(eventType: "state_changed") { [weak self] message in
                await self?.consumeStateChangedEvent(message)
            }
        }

        if lovelaceSubscriptionID == nil {
            lovelaceSubscriptionID = try await client.subscribe(eventType: "lovelace_updated") { [weak self] message in
                await self?.consumeLovelaceUpdatedEvent(message)
            }
        }
    }

    private func consumeStateChangedEvent(_ message: JSONDictionary) async {
        guard let data = message["event"]?.objectValue?["data"]?.objectValue else { return }
        guard let entityID = data["entity_id"]?.stringValue else { return }

        if data["new_state"] == .null {
            entityStates.removeValue(forKey: entityID)
            return
        }

        guard let newStateObject = data["new_state"]?.objectValue else { return }

        do {
            let json = JSONValue.object(newStateObject)
            let encoded = try JSONEncoder().encode(json)
            let state = try JSONDecoder().decode(HAEntityState.self, from: encoded)
            entityStates[state.entityID] = state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func consumeLovelaceUpdatedEvent(_ message: JSONDictionary) async {
        guard let selectedDashboard else { return }
        let eventData = message["event"]?.objectValue?["data"]?.objectValue
        let urlPath = eventData?["url_path"]?.stringValue

        if (urlPath ?? "") == (selectedDashboard.normalizedURLPath ?? "") {
            await reloadSelectedDashboard()
        }
    }

    private func preloadCameraURLs() async {
        guard let client, let dashboardConfig else { return }

        let cameraEntityIDs = Set<String>(
            dashboardConfig.allCards.compactMap { card in
                let cameraID = card.cameraEntityID
                guard let cameraID, state(for: cameraID)?.domain == "camera" else {
                    return nil
                }
                return cameraID
            }
        )

        for entityID in cameraEntityIDs {
            if cameraPreviewURLs[entityID] == nil {
                cameraPreviewURLs[entityID] = try? await client.signedCameraPreviewURL(entityID: entityID)
            }

            if cameraStreamURLs[entityID] == nil {
                cameraStreamURLs[entityID] = try? await client.signedCameraStreamURL(entityID: entityID)
            }
        }
    }
}
