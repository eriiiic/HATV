import Foundation
import Observation
import SwiftData
#if canImport(TVServices)
import TVServices
#endif

private let videoHubSelectionPath = "__hatv_video_hub__"

@MainActor
@Observable
final class RootViewModel {
    private enum FallbackActionDisposition {
        case control
        case moreInfo
    }

    enum Screen {
        case booting
        case connection
        case dashboardPicker
        case dashboard
    }

    struct CameraPresentationRequest: Equatable, Sendable {
        let entityIDs: [String]
        let startingIndex: Int
        let autoAdvance: Bool
    }

    struct MoreInfoPresentation: Identifiable, Equatable, Sendable {
        let entityID: String
        let preferredTitle: String?

        var id: String {
            preferredTitle.map { "\(entityID)|\($0)" } ?? entityID
        }
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
    var isShowingVideoHub = false
    var hiddenCameraEntityIDs: Set<String> = []
    var favoriteCameraEntityIDs: Set<String> = []
    var entityStates: [String: HAEntityState] = [:]
    var areaNamesByID: [String: String] = [:]
    var cameraAreaNamesByEntityID: [String: String] = [:]
    var cameraPreviewURLs: [String: URL] = [:]
    var cameraStreamURLs: [String: URL] = [:]
    var historySamplesByKey: [String: [HAHistorySample]] = [:]
    var statisticsSamplesByKey: [String: [HAHistorySample]] = [:]
    var weatherForecastsByKey: [String: [HAWeatherForecastEntry]] = [:]
    var logbookEntriesByKey: [String: [HALogbookEntry]] = [:]
    var energyPreferences: HAEnergyPreferences?
    var lastSuccessfulRefreshAt: Date?
    var autoLaunchDashboard = true
    var prefersMinimalChrome = true
    var isBusy = false
    var statusMessage = "Loading…"
    var errorMessage: String?
    var connectionProbeMessage: String?
    var externalCameraPresentation: CameraPresentationRequest?
    var moreInfoPresentation: MoreInfoPresentation?

    private(set) var didBootstrap = false
    private let tokenStore = KeychainTokenStore()
    private var client: HomeAssistantClient?
    private var stateSubscriptionID: Int?
    private var lovelaceSubscriptionID: Int?
    private var loadingHistoryKeys: Set<String> = []
    private var loadingStatisticsKeys: Set<String> = []
    private var loadingWeatherForecastKeys: Set<String> = []
    private var loadingLogbookKeys: Set<String> = []
    private var activeConnection: StoredConnection?
    private var activeModelContext: ModelContext?
    private let defaults = UserDefaults.standard
    private var pendingDeepLink: HATVDeepLink?

    var currentView: HALovelaceView? {
        guard let dashboardConfig, dashboardConfig.views.indices.contains(selectedViewIndex) else {
            return dashboardConfig?.views.first
        }
        return dashboardConfig.views[selectedViewIndex]
    }

    var allCameraStates: [HAEntityState] {
        entityStates.values
            .filter { $0.domain == "camera" }
            .sorted { lhs, rhs in
                lhs.friendlyName.localizedCaseInsensitiveCompare(rhs.friendlyName) == .orderedAscending
            }
    }

    var visibleCameraStates: [HAEntityState] {
        allCameraStates.filter { !hiddenCameraEntityIDs.contains($0.entityID) }
    }

    var hiddenCameraStates: [HAEntityState] {
        allCameraStates.filter { hiddenCameraEntityIDs.contains($0.entityID) }
    }

    var favoriteCameraStates: [HAEntityState] {
        allCameraStates.filter { favoriteCameraEntityIDs.contains($0.entityID) && !hiddenCameraEntityIDs.contains($0.entityID) }
    }

    var availableCameraAreas: [String] {
        Array(
            Set(
                allCameraStates.compactMap { cameraAreaNamesByEntityID[$0.entityID] }
            )
        )
        .sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    var lightsOnCount: Int {
        entityStates.values.filter { $0.domain == "light" && $0.isActive }.count
    }

    var activeClimateCount: Int {
        entityStates.values.filter { $0.domain == "climate" && $0.isActive }.count
    }

    var activeMediaCount: Int {
        entityStates.values.filter { $0.domain == "media_player" && $0.isActive }.count
    }

    var energyUsageStatisticID: String? {
        energyPreferences?.primaryPowerStatisticID
    }

    var preferredWeatherEntityID: String? {
        if entityStates["weather.forecast_maison"] != nil {
            return "weather.forecast_maison"
        }

        return entityStates.values
            .filter { $0.domain == "weather" }
            .sorted { $0.friendlyName.localizedCaseInsensitiveCompare($1.friendlyName) == .orderedAscending }
            .first?
            .entityID
    }

    func bootstrap(with storedConnection: StoredConnection?, modelContext: ModelContext) async {
        guard !didBootstrap else { return }
        didBootstrap = true
        activeConnection = storedConnection
        activeModelContext = modelContext
        loadConnectionPreferences()

        let debugOverride = DebugHomeAssistantOverride.load()

        guard let storedConnection else {
            await bootstrapWithoutStoredConnection(debugOverride, modelContext: modelContext)
            return
        }

        connectionName = storedConnection.name
        serverURLString = storedConnection.baseURLString
        autoLaunchDashboard = storedConnection.autoLaunchDashboard

        do {
            if let token = try tokenStore.load(account: storedConnection.id), !token.isEmpty {
                accessToken = token
                try await connectSession(
                    name: storedConnection.name,
                    baseURLString: storedConnection.baseURLString,
                    token: token,
                    storedConnection: storedConnection,
                    autoLaunchSelection: storedConnection.autoLaunchDashboard
                )
                return
            }

            if let debugOverride, canApply(debugOverride, to: storedConnection) {
                connectionName = debugOverride.name
                serverURLString = debugOverride.baseURLString
                accessToken = debugOverride.accessToken

                storedConnection.name = debugOverride.name
                storedConnection.baseURLString = debugOverride.baseURLString
                storedConnection.updatedAt = .now
                try? modelContext.save()
                try tokenStore.save(debugOverride.accessToken, account: storedConnection.id)

                if debugOverride.autoConnect {
                    try await connectSession(
                        name: storedConnection.name,
                        baseURLString: storedConnection.baseURLString,
                        token: debugOverride.accessToken,
                        storedConnection: storedConnection,
                        autoLaunchSelection: storedConnection.autoLaunchDashboard
                    )
                } else {
                    screen = .connection
                }

                return
            }

            if let debugOverride {
                apply(debugOverride)
            }

            screen = .connection
        } catch {
            screen = .connection
            present(error, context: "Startup")
        }
    }

    func connect(modelContext: ModelContext, storedConnection: StoredConnection?) async {
        errorMessage = nil
        connectionProbeMessage = nil
        activeConnection = storedConnection
        activeModelContext = modelContext
        loadConnectionPreferences()

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
            persisted.autoLaunchDashboard = autoLaunchDashboard
            activeConnection = persisted
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
            present(error, context: "Connection")
            screen = .connection
        }
    }

    func testConnection() async {
        errorMessage = nil
        connectionProbeMessage = nil

        let trimmedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty, !trimmedToken.isEmpty else {
            errorMessage = "Enter a Home Assistant URL and long-lived access token."
            return
        }

        guard let url = normalizedURL(from: trimmedURL) else {
            errorMessage = HomeAssistantClientError.invalidURL.localizedDescription
            return
        }

        isBusy = true
        statusMessage = "Testing server…"
        defer { isBusy = false }

        do {
            let probeClient = HomeAssistantClient(baseURL: url, token: trimmedToken)
            let info = try await probeClient.validateConnection()
            let availableDashboards = try await probeClient.fetchDashboards()
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            await probeClient.disconnect()

            instanceInfo = info
            dashboards = availableDashboards
            connectionProbeMessage = availableDashboards.isEmpty
                ? "Connected, but this account cannot see any Lovelace dashboards yet."
                : "Connected to \(info.locationName). \(availableDashboards.count) dashboard\(availableDashboards.count == 1 ? "" : "s") ready."
        } catch {
            present(error, context: "Connection Test")
        }
    }

    func chooseDashboard(
        _ dashboard: HADashboardSummary,
        storedConnection: StoredConnection?,
        modelContext: ModelContext
    ) async {
        activeConnection = storedConnection ?? activeConnection
        activeModelContext = modelContext
        selectedDashboard = dashboard

        if let storedConnection = activeConnection {
            let isSameDashboard =
                storedConnection.selectedDashboardID == dashboard.id
                || storedConnection.selectedDashboardURLPath == dashboard.normalizedURLPath

            if !isSameDashboard {
                storedConnection.selectedViewPath = nil
                storedConnection.selectedViewTitle = nil
            }

            storedConnection.selectedDashboardID = dashboard.id
            storedConnection.selectedDashboardURLPath = dashboard.normalizedURLPath
            storedConnection.selectedDashboardTitle = dashboard.title
            storedConnection.updatedAt = .now
            persistConnection()
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

            let storedSelectionPath = activeConnection?.selectedViewPath
            isShowingVideoHub = storedSelectionPath == videoHubSelectionPath

            if let preferredIndex = dashboardConfig?.preferredViewIndex(
                path: isShowingVideoHub ? nil : storedSelectionPath,
                title: isShowingVideoHub ? nil : activeConnection?.selectedViewTitle
            ) {
                selectedViewIndex = preferredIndex
            } else {
                selectedViewIndex = 0
            }

            persistCurrentViewSelection()
            screen = .dashboard
            lastSuccessfulRefreshAt = .now
            await preloadCurrentViewData()

            if isShowingVideoHub {
                await preloadAllCameraURLs()
            }

            publishTopShelfSnapshot()
            await applyPendingDeepLinkIfPossible()
        } catch {
            present(error, context: "Dashboard")
        }
    }

    func showDashboardPicker() {
        screen = .dashboardPicker
        publishTopShelfSnapshot()
    }

    func showConnectionEditor() {
        screen = .connection
    }

    func refreshDashboard() async {
        if selectedDashboard != nil {
            await reloadSelectedDashboard()
        }
    }

    func reconnectCurrentSession() async {
        guard let activeConnection else {
            screen = .connection
            return
        }

        do {
            guard let token = try tokenStore.load(account: activeConnection.id), !token.isEmpty else {
                screen = .connection
                return
            }

            try await connectSession(
                name: activeConnection.name,
                baseURLString: activeConnection.baseURLString,
                token: token,
                storedConnection: activeConnection,
                autoLaunchSelection: activeConnection.autoLaunchDashboard
            )
        } catch {
            present(error, context: "Reconnect")
        }
    }

    func setMinimalChromePreference(_ value: Bool) {
        prefersMinimalChrome = value
        persistMinimalChromePreference()
    }

    func setAutoLaunchDashboardPreference(_ value: Bool) {
        autoLaunchDashboard = value
        activeConnection?.autoLaunchDashboard = value
        activeConnection?.updatedAt = .now
        persistConnection()
    }

    func selectView(_ view: HALovelaceView) {
        guard let dashboardConfig else { return }
        if let index = dashboardConfig.views.firstIndex(where: { $0.id == view.id }) {
            isShowingVideoHub = false
            applySelectedView(at: index)
        }
    }

    func showVideoHub() async {
        isShowingVideoHub = true
        persistCurrentViewSelection()
        await preloadAllCameraURLs()
        publishTopShelfSnapshot()
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

    func isCameraHidden(_ entityID: String?) -> Bool {
        guard let entityID else { return false }
        return hiddenCameraEntityIDs.contains(entityID)
    }

    func isCameraFavorite(_ entityID: String?) -> Bool {
        guard let entityID else { return false }
        return favoriteCameraEntityIDs.contains(entityID)
    }

    func cameraAreaName(for entityID: String) -> String? {
        cameraAreaNamesByEntityID[entityID]
    }

    func cameras(inArea named: String) -> [HAEntityState] {
        visibleCameraStates.filter { cameraAreaNamesByEntityID[$0.entityID] == named }
    }

    func hideCamera(_ entityID: String) {
        hiddenCameraEntityIDs.insert(entityID)
        persistHiddenCameraPreferences()
        publishTopShelfSnapshot()
    }

    func unhideCamera(_ entityID: String) {
        hiddenCameraEntityIDs.remove(entityID)
        persistHiddenCameraPreferences()
        publishTopShelfSnapshot()
    }

    func toggleFavoriteCamera(_ entityID: String) {
        if favoriteCameraEntityIDs.contains(entityID) {
            favoriteCameraEntityIDs.remove(entityID)
        } else {
            favoriteCameraEntityIDs.insert(entityID)
        }
        persistFavoriteCameraPreferences()
        publishTopShelfSnapshot()
    }

    func handleIncomingURL(
        _ url: URL,
        storedConnection: StoredConnection?,
        modelContext: ModelContext
    ) async {
        activeConnection = storedConnection ?? activeConnection
        activeModelContext = modelContext

        guard let deepLink = HATVDeepLink(url: url) else {
            return
        }

        pendingDeepLink = deepLink
        await applyPendingDeepLinkIfPossible()
    }

    func shouldDisplayCard(_ card: HAAnyConfig) -> Bool {
        if let cameraEntityID = card.cameraEntityID, isCameraHidden(cameraEntityID) {
            return false
        }

        if card.type == "heading",
           card.primaryText == nil,
           card.secondaryText == nil,
           card.entityID == nil,
           card.navigationPath == nil {
            return false
        }

        if !card.childCards.isEmpty {
            return card.childCards.contains(where: shouldDisplayCard)
        }

        return true
    }

    func loadCameraStreamURL(for entityID: String, refresh: Bool = false) async throws -> URL {
        guard let client else {
            throw HomeAssistantClientError.missingSocket
        }

        if !refresh, let cachedURL = cameraStreamURLs[entityID] {
            return cachedURL
        }

        let streamURL = try await client.signedCameraStreamURL(entityID: entityID)
        cameraStreamURLs[entityID] = streamURL
        return streamURL
    }

    func historySamples(for entityID: String, hours: Int) -> [HAHistorySample] {
        historySamplesByKey[historyKey(entityID: entityID, hours: hours)] ?? []
    }

    func isLoadingHistory(for entityID: String, hours: Int) -> Bool {
        loadingHistoryKeys.contains(historyKey(entityID: entityID, hours: hours))
    }

    func statisticsSamples(
        for statisticID: String,
        hours: Int,
        period: HAStatisticsPeriod = .hour
    ) -> [HAHistorySample] {
        statisticsSamplesByKey[statisticsKey(statisticID: statisticID, hours: hours, period: period)] ?? []
    }

    func weatherForecast(for entityID: String, type: HAWeatherForecastType) -> [HAWeatherForecastEntry] {
        weatherForecastsByKey[weatherForecastKey(entityID: entityID, type: type)] ?? []
    }

    func logbookEntries(for card: HAAnyConfig) -> [HALogbookEntry] {
        let key = logbookKey(
            entityIDs: card.logbookEntityIDs,
            hours: card.miniGraphHoursToShow,
            stateFilter: card.logbookStateFilter
        )
        return logbookEntriesByKey[key] ?? []
    }

    func loadHistoryIfNeeded(for entityID: String, hours: Int) async {
        guard let client else { return }

        let key = historyKey(entityID: entityID, hours: hours)
        guard historySamplesByKey[key] == nil, !loadingHistoryKeys.contains(key) else {
            return
        }

        loadingHistoryKeys.insert(key)
        defer { loadingHistoryKeys.remove(key) }

        do {
            historySamplesByKey[key] = try await client.fetchHistory(entityID: entityID, hours: hours)
        } catch {
            present(error, context: "History")
        }
    }

    func loadStatisticsIfNeeded(
        for statisticID: String,
        hours: Int,
        period: HAStatisticsPeriod = .hour
    ) async {
        guard let client else { return }

        let key = statisticsKey(statisticID: statisticID, hours: hours, period: period)
        guard statisticsSamplesByKey[key] == nil, !loadingStatisticsKeys.contains(key) else {
            return
        }

        loadingStatisticsKeys.insert(key)
        defer { loadingStatisticsKeys.remove(key) }

        do {
            statisticsSamplesByKey[key] = try await client.fetchStatistics(
                statisticID: statisticID,
                hours: hours,
                period: period
            )
        } catch {
            present(error, context: "Statistics")
        }
    }

    func loadEnergyUsageIfNeeded(hours: Int = 24) async {
        guard let client else { return }

        if energyPreferences == nil {
            do {
                energyPreferences = try await client.fetchEnergyPreferences()
            } catch {
                present(error, context: "Energy")
                return
            }
        }

        guard let statisticID = energyPreferences?.primaryPowerStatisticID else {
            return
        }

        await loadStatisticsIfNeeded(for: statisticID, hours: hours, period: .hour)
    }

    func loadWeatherForecastIfNeeded(for entityID: String, type: HAWeatherForecastType) async {
        guard let client else { return }

        let key = weatherForecastKey(entityID: entityID, type: type)
        guard weatherForecastsByKey[key] == nil, !loadingWeatherForecastKeys.contains(key) else {
            return
        }

        loadingWeatherForecastKeys.insert(key)
        defer { loadingWeatherForecastKeys.remove(key) }

        do {
            weatherForecastsByKey[key] = try await client.fetchWeatherForecast(entityID: entityID, type: type)
        } catch {
            print("[HATV] Weather forecast: \(error.localizedDescription)")
        }
    }

    func loadLogbookIfNeeded(
        entityIDs: [String],
        hours: Int,
        stateFilter: [String] = []
    ) async {
        guard let client else { return }

        let key = logbookKey(entityIDs: entityIDs, hours: hours, stateFilter: stateFilter)
        guard logbookEntriesByKey[key] == nil, !loadingLogbookKeys.contains(key) else {
            return
        }

        loadingLogbookKeys.insert(key)
        defer { loadingLogbookKeys.remove(key) }

        do {
            logbookEntriesByKey[key] = try await client.fetchLogbook(
                entityIDs: entityIDs,
                hours: hours,
                stateFilter: stateFilter
            )
        } catch {
            print("[HATV] Logbook: \(error.localizedDescription)")
        }
    }

    func executePrimaryAction(for card: HAAnyConfig) async {
        await executeAction(
            card.primaryAction,
            fallbackEntityID: card.primaryEntityID,
            fallbackTitle: card.primaryText ?? card.title ?? card.heading
        )
    }

    func executePrimaryAction(for item: HAEntityItem) async {
        await executeAction(
            item.action,
            fallbackEntityID: item.entityID,
            fallbackTitle: item.name ?? entityStates[item.entityID]?.friendlyName ?? item.entityID
        )
    }

    func dismissMoreInfo() {
        moreInfoPresentation = nil
    }

    func toggleEntity(_ entityID: String) async {
        do {
            try await performDefaultAction(for: entityID)
        } catch {
            present(error, context: "Action")
        }
    }

    func adjustLightBrightness(for entityID: String, deltaPercent: Int) async {
        guard let state = entityStates[entityID] else { return }

        let current = state.brightnessPercent ?? (state.isActive ? 100 : 0)
        let nextValue = min(max(current + deltaPercent, 1), 100)

        await callService(
            named: "light.turn_on",
            targetEntityIDs: [entityID],
            serviceData: ["brightness_pct": .number(Double(nextValue))]
        )
    }

    func adjustClimateTemperature(for entityID: String, delta: Double) async {
        guard let state = entityStates[entityID] else { return }

        let current = state.targetTemperature ?? state.currentTemperature ?? state.numericState
        guard let current else { return }

        let nextValue = max(current + delta, 5)
        await callService(
            named: "climate.set_temperature",
            targetEntityIDs: [entityID],
            serviceData: ["temperature": .number(nextValue)]
        )
    }

    func toggleClimatePower(for entityID: String) async {
        guard let state = entityStates[entityID] else { return }

        let isCurrentlyOff = ["off", "unavailable", "unknown"].contains(state.state.lowercased())
        await callService(
            named: isCurrentlyOff ? "climate.turn_on" : "climate.turn_off",
            targetEntityIDs: [entityID]
        )
    }

    func toggleMediaPlayback(for entityID: String) async {
        await callService(named: "media_player.media_play_pause", targetEntityIDs: [entityID])
    }

    func adjustMediaVolume(for entityID: String, deltaPercent: Int) async {
        let current = entityStates[entityID]?.volumePercent ?? 0
        let nextValue = min(max(current + deltaPercent, 0), 100)

        await callService(
            named: "media_player.volume_set",
            targetEntityIDs: [entityID],
            serviceData: ["volume_level": .number(Double(nextValue) / 100.0)]
        )
    }

    func performCoverCommand(for entityID: String, action: CoverAction) async {
        let serviceName: String
        switch action {
        case .open:
            serviceName = "cover.open_cover"
        case .stop:
            serviceName = "cover.stop_cover"
        case .close:
            serviceName = "cover.close_cover"
        }

        await callService(named: serviceName, targetEntityIDs: [entityID])
    }

    func performLockCommand(for entityID: String, action: LockAction) async {
        let serviceName: String
        switch action {
        case .lock:
            serviceName = "lock.lock"
        case .unlock:
            serviceName = "lock.unlock"
        }

        await callService(named: serviceName, targetEntityIDs: [entityID])
    }

    private func executeAction(
        _ action: HAActionConfig?,
        fallbackEntityID: String?,
        fallbackTitle: String? = nil
    ) async {
        if action?.kind == "none" {
            return
        }

        if action?.kind == "more-info" {
            presentMoreInfo(
                for: action?.entityIDOverride ?? fallbackEntityID,
                preferredTitle: fallbackTitle
            )
            return
        }

        do {
            if let action {
                switch action.kind {
                case "navigate":
                    if let navigationPath = action.navigationPath {
                        navigate(to: navigationPath)
                    }
                case "call-service", "perform-action":
                    if let serviceName = action.serviceName, let client {
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
                    if let fallbackEntityID, let client {
                        try await client.callService(named: "homeassistant.toggle", targetEntityIDs: [fallbackEntityID])
                    }
                default:
                    if let fallbackEntityID {
                        try await performDefaultAction(for: fallbackEntityID)
                    }
                }
            } else if let fallbackEntityID {
                switch fallbackActionDisposition(for: fallbackEntityID) {
                case .control:
                    try await performDefaultAction(for: fallbackEntityID)
                case .moreInfo:
                    presentMoreInfo(for: fallbackEntityID, preferredTitle: fallbackTitle)
                }
            }
        } catch {
            present(error, context: "Action")
        }
    }

    private func callService(
        named serviceName: String,
        targetEntityIDs: [String],
        serviceData: JSONDictionary = [:]
    ) async {
        guard let client else { return }

        do {
            try await client.callService(
                named: serviceName,
                targetEntityIDs: targetEntityIDs,
                serviceData: serviceData
            )
        } catch {
            present(error, context: "Action")
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

        isShowingVideoHub = false
        applySelectedView(at: index)
    }

    private func presentMoreInfo(for entityID: String?, preferredTitle: String?) {
        guard let entityID, !entityID.isEmpty else {
            errorMessage = "No entity is associated with this Home Assistant action."
            return
        }

        moreInfoPresentation = MoreInfoPresentation(
            entityID: entityID,
            preferredTitle: preferredTitle
        )
    }

    private func fallbackActionDisposition(for entityID: String) -> FallbackActionDisposition {
        guard let state = entityStates[entityID] else {
            return .moreInfo
        }

        switch state.domain {
        case "button", "input_button", "scene", "script", "cover", "lock":
            return .control
        default:
            return state.isToggleLike ? .control : .moreInfo
        }
    }

    private func applyDebugMoreInfoOverrideIfNeeded() {
        #if DEBUG
        guard let debugOverride = DebugHomeAssistantOverride.load(),
              let entityID = debugOverride.moreInfoEntityID,
              entityStates[entityID] != nil else {
            return
        }

        presentMoreInfo(for: entityID, preferredTitle: debugOverride.moreInfoTitle)
        #endif
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
        connectionProbeMessage = nil
        defer { isBusy = false }
        activeConnection = storedConnection ?? activeConnection

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
        areaNamesByID = [:]
        cameraAreaNamesByEntityID = [:]
        cameraPreviewURLs = [:]
        cameraStreamURLs = [:]
        historySamplesByKey = [:]
        statisticsSamplesByKey = [:]
        weatherForecastsByKey = [:]
        logbookEntriesByKey = [:]
        energyPreferences = nil
        lastSuccessfulRefreshAt = .now
        loadingHistoryKeys.removeAll()
        loadingStatisticsKeys.removeAll()
        loadingWeatherForecastKeys.removeAll()
        loadingLogbookKeys.removeAll()
        self.dashboards = dashboards.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        loadConnectionPreferences()

        do {
            let areas = try await nextClient.fetchAreaRegistry()
            let entities = try await nextClient.fetchEntityRegistry()
            applyCameraRegistry(areas: areas, entities: entities)
        } catch {
            print("[HATV] Registry: \(error.localizedDescription)")
        }

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

        publishTopShelfSnapshot()
        await applyPendingDeepLinkIfPossible()
        applyDebugMoreInfoOverrideIfNeeded()
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
        connection.autoLaunchDashboard = autoLaunchDashboard
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
            publishTopShelfSnapshotIfRelevant(entityID: entityID, domain: state.domain)
        } catch {
            present(error, context: "Live update")
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

    private func preloadAllCameraURLs() async {
        await preloadCameraURLs(for: allCameraStates.map(\.entityID), includeStreamURLs: false)
    }

    private func preloadCurrentViewData() async {
        guard !isShowingVideoHub, let currentView else { return }

        let cards = currentView.allCards.filter(viewModelDisplayability)
        let cameraIDs = cards.compactMap { card -> String? in
            guard let cameraID = card.cameraEntityID,
                  !hiddenCameraEntityIDs.contains(cameraID),
                  state(for: cameraID)?.domain == "camera" else {
                return nil
            }
            return cameraID
        }

        await preloadCameraURLs(for: cameraIDs, includeStreamURLs: true)

        for card in cards {
            if card.type == "weather-forecast", let entityID = card.entityID {
                await loadWeatherForecastIfNeeded(for: entityID, type: card.weatherForecastType)
            }

            if card.type == "custom:hourly-weather", let entityID = card.entityID {
                await loadWeatherForecastIfNeeded(for: entityID, type: .hourly)
            }

            if card.type == "custom:weather-chart-card", let entityID = card.entityID {
                await loadWeatherForecastIfNeeded(for: entityID, type: card.weatherChartForecastType)
            }

            if card.type == "custom:weather-radar-card", let entityID = preferredWeatherEntityID {
                await loadWeatherForecastIfNeeded(for: entityID, type: .hourly)
            }

            if card.type == "logbook" {
                await loadLogbookIfNeeded(
                    entityIDs: card.logbookEntityIDs,
                    hours: card.miniGraphHoursToShow,
                    stateFilter: card.logbookStateFilter
                )
            }

            if card.prefersTrendVisualization {
                if card.type == "energy-usage-graph" {
                    await loadEnergyUsageIfNeeded(hours: card.miniGraphHoursToShow)
                } else if let graphEntityID = card.graphEntityIDs.first {
                    await loadHistoryIfNeeded(for: graphEntityID, hours: card.miniGraphHoursToShow)
                }
            }
        }
    }

    private func preloadCameraURLs(for entityIDs: [String], includeStreamURLs: Bool) async {
        guard let client else { return }

        for entityID in Set(entityIDs) {
            if cameraPreviewURLs[entityID] == nil {
                cameraPreviewURLs[entityID] = try? await client.signedCameraPreviewURL(entityID: entityID)
            }

            if includeStreamURLs, cameraStreamURLs[entityID] == nil {
                cameraStreamURLs[entityID] = try? await client.signedCameraStreamURL(entityID: entityID)
            }
        }
    }

    private func bootstrapWithoutStoredConnection(
        _ debugOverride: DebugHomeAssistantOverride?,
        modelContext: ModelContext
    ) async {
        guard let debugOverride else {
            screen = .connection
            return
        }

        apply(debugOverride)

        do {
            let persisted = upsertConnection(
                named: debugOverride.name,
                baseURLString: debugOverride.baseURLString,
                in: modelContext,
                existing: nil
            )
            activeConnection = persisted
            activeModelContext = modelContext
            try tokenStore.save(debugOverride.accessToken, account: persisted.id)

            if debugOverride.autoConnect {
                try await connectSession(
                    name: persisted.name,
                    baseURLString: persisted.baseURLString,
                    token: debugOverride.accessToken,
                    storedConnection: persisted,
                    autoLaunchSelection: persisted.autoLaunchDashboard
                )
            } else {
                screen = .connection
            }
        } catch {
            screen = .connection
            present(error, context: "Startup")
        }
    }

    private func apply(_ debugOverride: DebugHomeAssistantOverride) {
        connectionName = debugOverride.name
        serverURLString = debugOverride.baseURLString
        accessToken = debugOverride.accessToken
    }

    private func canApply(_ debugOverride: DebugHomeAssistantOverride, to connection: StoredConnection) -> Bool {
        if connection.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        let current = normalizedURL(from: connection.baseURLString)?.absoluteString
        let debug = normalizedURL(from: debugOverride.baseURLString)?.absoluteString
        return current == debug
    }

    private func present(_ error: Error, context: String) {
        let message = error.userFacingMessage(context: context)
        errorMessage = message
        print("[HATV] \(message)")
    }

    private func historyKey(entityID: String, hours: Int) -> String {
        "\(entityID)|\(hours)"
    }

    private func statisticsKey(
        statisticID: String,
        hours: Int,
        period: HAStatisticsPeriod
    ) -> String {
        "\(statisticID)|\(hours)|\(period.rawValue)"
    }

    private func weatherForecastKey(entityID: String, type: HAWeatherForecastType) -> String {
        "\(entityID)|\(type.rawValue)"
    }

    private func applySelectedView(at index: Int) {
        guard let dashboardConfig, dashboardConfig.views.indices.contains(index) else {
            return
        }

        selectedViewIndex = index
        persistCurrentViewSelection()
        publishTopShelfSnapshot()

        Task {
            await preloadCurrentViewData()
        }
    }

    private func persistCurrentViewSelection() {
        guard let activeConnection else { return }

        if isShowingVideoHub {
            activeConnection.selectedViewPath = videoHubSelectionPath
            activeConnection.selectedViewTitle = "Video"
        } else {
            activeConnection.selectedViewPath = currentView?.path
            activeConnection.selectedViewTitle = currentView?.displayTitle
        }
        activeConnection.updatedAt = .now
        persistConnection()
    }

    private func persistConnection() {
        try? activeModelContext?.save()
    }

    private func dashboardCameraEntityIDs() -> [String] {
        guard let dashboardConfig else { return [] }

        return Array(
            Set(
                dashboardConfig.allCards.compactMap { card in
                    guard let cameraID = card.cameraEntityID,
                          !hiddenCameraEntityIDs.contains(cameraID),
                          state(for: cameraID)?.domain == "camera" else {
                        return nil
                    }
                    return cameraID
                }
            )
        )
    }

    private func applyCameraRegistry(
        areas: [HAAreaRegistryEntry],
        entities: [HAEntityRegistryEntry]
    ) {
        areaNamesByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.name) })
        cameraAreaNamesByEntityID = Dictionary(
            uniqueKeysWithValues: entities.compactMap { entry in
                guard let areaID = entry.areaID,
                      let areaName = areaNamesByID[areaID],
                      state(for: entry.entityID)?.domain == "camera" else {
                    return nil
                }

                return (entry.entityID, areaName)
            }
        )
        publishTopShelfSnapshot()
    }

    private func loadConnectionPreferences() {
        autoLaunchDashboard = activeConnection?.autoLaunchDashboard ?? true
        loadHiddenCameraPreferences()
        loadFavoriteCameraPreferences()
        loadMinimalChromePreference()
    }

    private func loadHiddenCameraPreferences() {
        let values = defaults.stringArray(forKey: hiddenCameraPreferenceKey()) ?? []
        hiddenCameraEntityIDs = Set(values)
    }

    private func persistHiddenCameraPreferences() {
        defaults.set(Array(hiddenCameraEntityIDs).sorted(), forKey: hiddenCameraPreferenceKey())
    }

    private func hiddenCameraPreferenceKey() -> String {
        "hatv.hidden-cameras.\(activeConnection?.id ?? StoredConnection.defaultID)"
    }

    private func loadFavoriteCameraPreferences() {
        let values = defaults.stringArray(forKey: favoriteCameraPreferenceKey()) ?? []
        favoriteCameraEntityIDs = Set(values)
    }

    private func persistFavoriteCameraPreferences() {
        defaults.set(Array(favoriteCameraEntityIDs).sorted(), forKey: favoriteCameraPreferenceKey())
    }

    private func favoriteCameraPreferenceKey() -> String {
        "hatv.favorite-cameras.\(activeConnection?.id ?? StoredConnection.defaultID)"
    }

    private func loadMinimalChromePreference() {
        let key = minimalChromePreferenceKey()
        if defaults.object(forKey: key) == nil {
            prefersMinimalChrome = true
        } else {
            prefersMinimalChrome = defaults.bool(forKey: key)
        }
    }

    private func persistMinimalChromePreference() {
        defaults.set(prefersMinimalChrome, forKey: minimalChromePreferenceKey())
    }

    private func minimalChromePreferenceKey() -> String {
        "hatv.minimal-chrome.\(activeConnection?.id ?? StoredConnection.defaultID)"
    }

    private func logbookKey(entityIDs: [String], hours: Int, stateFilter: [String]) -> String {
        let normalizedEntityIDs = Array(Set(entityIDs)).sorted().joined(separator: ",")
        let normalizedStateFilter = Array(Set(stateFilter.map { $0.lowercased() })).sorted().joined(separator: ",")
        return "\(normalizedEntityIDs)|\(hours)|\(normalizedStateFilter)"
    }

    private func viewModelDisplayability(_ card: HAAnyConfig) -> Bool {
        shouldDisplayCard(card)
    }

    private func applyPendingDeepLinkIfPossible() async {
        guard let pendingDeepLink else { return }

        if screen == .connection || screen == .booting || client == nil {
            return
        }

        if selectedDashboard == nil {
            if let activeConnection,
               let dashboard = matchingDashboard(for: activeConnection, dashboards: dashboards) ?? dashboards.first {
                selectedDashboard = dashboard
                await reloadSelectedDashboard()
                return
            } else if let firstDashboard = dashboards.first {
                selectedDashboard = firstDashboard
                await reloadSelectedDashboard()
                return
            }
        }

        switch pendingDeepLink {
        case .home:
            screen = .dashboard
        case .video:
            await showVideoHub()
            screen = .dashboard
        case .dashboard(let viewPath):
            if let viewPath,
               let dashboardConfig,
               let matchingView = dashboardConfig.views.first(where: { $0.matchesNavigationPath(viewPath) }) {
                selectView(matchingView)
            } else {
                isShowingVideoHub = false
                persistCurrentViewSelection()
                publishTopShelfSnapshot()
            }
            screen = .dashboard
        case .camera(let entityID):
            await showVideoHub()
            externalCameraPresentation = CameraPresentationRequest(
                entityIDs: [entityID],
                startingIndex: 0,
                autoAdvance: false
            )
            screen = .dashboard
        }

        self.pendingDeepLink = nil
    }

    private func publishTopShelfSnapshotIfRelevant(entityID: String, domain: String) {
        let relevantDomains: Set<String> = ["camera", "light", "climate", "media_player", "weather"]
        if relevantDomains.contains(domain) || favoriteCameraEntityIDs.contains(entityID) || hiddenCameraEntityIDs.contains(entityID) {
            publishTopShelfSnapshot()
        }
    }

    private func publishTopShelfSnapshot() {
        guard let snapshot = currentTopShelfSnapshot() else {
            HATVTopShelfSnapshotStore.clear()
            notifyTopShelfContentChanged()
            return
        }

        HATVTopShelfSnapshotStore.write(snapshot)
        notifyTopShelfContentChanged()
    }

    private func currentTopShelfSnapshot() -> HATVTopShelfSnapshot? {
        guard !serverURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let preferredCameraStates = favoriteCameraStates.isEmpty ? visibleCameraStates : favoriteCameraStates
        let cameraShortcuts = preferredCameraStates.prefix(4).map { camera in
            HATVTopShelfCameraSnapshot(
                entityID: camera.entityID,
                title: camera.friendlyName,
                subtitle: cameraAreaName(for: camera.entityID) ?? camera.displayState
            )
        }

        return HATVTopShelfSnapshot(
            locationName: instanceInfo?.locationName,
            dashboardTitle: selectedDashboard?.title ?? activeConnection?.selectedDashboardTitle,
            viewTitle: isShowingVideoHub ? "Video Wall" : (currentView?.displayTitle ?? activeConnection?.selectedViewTitle),
            viewPath: isShowingVideoHub ? videoHubSelectionPath : (currentView?.path ?? activeConnection?.selectedViewPath),
            isShowingVideoHub: isShowingVideoHub,
            visibleCameraCount: visibleCameraStates.count,
            favoriteCameraCount: favoriteCameraStates.count,
            lightsOnCount: lightsOnCount,
            activeClimateCount: activeClimateCount,
            activeMediaCount: activeMediaCount,
            cameraShortcuts: cameraShortcuts,
            updatedAt: .now
        )
    }

    private func notifyTopShelfContentChanged() {
#if canImport(TVServices)
        TVTopShelfContentProvider.topShelfContentDidChange()
#endif
    }
}

extension RootViewModel {
    enum CoverAction {
        case open
        case stop
        case close
    }

    enum LockAction {
        case lock
        case unlock
    }
}
