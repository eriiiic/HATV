import Charts
import Observation
import SwiftUI

private let templateStateRegex = try? NSRegularExpression(
    pattern: #"\{\{\s*states\(['"]([^'"]+)['"]\)\s*\}\}"#,
    options: []
)

private let mdiSymbolMap: [String: String] = [
    "bed": "bed.double.fill",
    "button-pointer": "cursorarrow.click.2",
    "home-thermometer": "thermometer.house.fill",
    "lightbulb-group": "lightbulb.max.fill",
    "television": "tv.fill",
    "thermostat": "thermometer.medium",
    "transmission-tower": "antenna.radiowaves.left.and.right",
    "washing-machine": "washer.fill",
    "weather-partly-cloudy": "cloud.sun.fill"
]

struct DashboardCardContent: View {
    let card: HAAnyConfig
    @Bindable var viewModel: RootViewModel
    let openCamera: (String, String) -> Void

    var body: some View {
        switch card.type {
        case "heading":
            headingCard
        case "entities":
            entitiesCard
        case "glance":
            glanceCard
        case "grid":
            nestedGridCard
        case "horizontal-stack":
            stackCard(axis: .horizontal)
        case "vertical-stack":
            stackCard(axis: .vertical)
        case "picture-entity", "picture-glance":
            cameraCard
        case "tile":
            tileCard
        case "button":
            buttonCard
        case "sensor", "custom:mini-graph-card":
            sensorTrendCard
        case "media-control":
            mediaControlCard
        case "custom:button-card":
            customButtonCard
        case "custom:room-summary-card":
            roomSummaryCard
        case "custom:better-thermostat-ui-card":
            thermostatCard
        case "custom:mushroom-light-card":
            mushroomLightCard
        case "custom:mushroom-template-card":
            mushroomTemplateCard
        case "custom:mushroom-chips-card":
            mushroomChipsCard
        default:
            if let entityID = card.cameraEntityID, viewModel.state(for: entityID)?.domain == "camera" {
                cameraCard
            } else {
                actionTileCard
            }
        }
    }

    private var actionTileCard: some View {
        let state = entityState
        let accent = accentColor(for: state)

        return Button {
            Task { await viewModel.executePrimaryAction(for: card) }
        } label: {
            cardContainer(accent: accent) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "square.grid.2x2.fill"))

                        Spacer()

                        Text(state?.displayState ?? "Ready")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.82))
                    }

                    Text(primaryTitle(for: state))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    if let subtitle = secondaryTitle(for: state) {
                        Text(subtitle)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var headingCard: some View {
        let accent = accentColor(for: nil)

        return cardContainer(accent: accent, minHeight: 148) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    iconBadge(symbolName: symbolName(for: nil, rawIcon: card.icon, fallback: "sparkles"))
                    Text(primaryTitle(for: nil))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                if let subtitle = secondaryTitle(for: nil) {
                    Text(subtitle)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }
        }
    }

    private var entitiesCard: some View {
        let accent = accentColor(for: entityState)

        return cardContainer(accent: accent, minHeight: 260) {
            VStack(alignment: .leading, spacing: 18) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                ForEach(card.entities, id: \.entityID) { item in
                    Button {
                        Task { await viewModel.executePrimaryAction(for: item) }
                    } label: {
                        entityRow(for: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var glanceCard: some View {
        let accent = accentColor(for: entityState)

        return cardContainer(accent: accent, minHeight: 260) {
            VStack(alignment: .leading, spacing: 18) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                    ForEach(card.entities, id: \.entityID) { item in
                        let state = viewModel.state(for: item.entityID)

                        Button {
                            Task { await viewModel.executePrimaryAction(for: item) }
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: symbolName(for: state, rawIcon: item.icon, fallback: "circle.fill"))
                                    .font(.title.bold())
                                    .foregroundStyle(.white)

                                Text(item.name ?? state?.friendlyName ?? item.entityID)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)

                                Text(state?.displayState ?? "Unknown")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .padding(14)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var nestedGridCard: some View {
        let accent = accentColor(for: entityState)
        let visibleChildCards = card.childCards.filter(viewModel.shouldDisplayCard)

        return cardContainer(accent: accent, minHeight: 260) {
            VStack(alignment: .leading, spacing: 18) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: max(card.columns, 1)),
                    spacing: 18
                ) {
                    ForEach(visibleChildCards) { child in
                        DashboardCardContent(card: child, viewModel: viewModel, openCamera: openCamera)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stackCard(axis: Axis) -> some View {
        let accent = accentColor(for: entityState)
        let visibleChildCards = card.childCards.filter(viewModel.shouldDisplayCard)

        cardContainer(accent: accent, minHeight: 220) {
            VStack(alignment: .leading, spacing: 18) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                if axis == .horizontal {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(visibleChildCards) { child in
                            DashboardCardContent(card: child, viewModel: viewModel, openCamera: openCamera)
                        }
                    }
                } else {
                    VStack(spacing: 18) {
                        ForEach(visibleChildCards) { child in
                            DashboardCardContent(card: child, viewModel: viewModel, openCamera: openCamera)
                        }
                    }
                }
            }
        }
    }

    private var cameraCard: some View {
        let entityID = card.cameraEntityID ?? ""
        let state = viewModel.state(for: entityID)
        let previewURL = viewModel.cameraPreviewURL(for: entityID)

        return DashboardCameraTile(
            title: state?.friendlyName ?? primaryTitle(for: state),
            subtitle: state?.displayState ?? "Live",
            detail: state?.subtitle ?? "Open full screen",
            previewURL: previewURL
        ) {
            openCamera(entityID, state?.friendlyName ?? primaryTitle(for: state))
        }
    }

    private var tileCard: some View {
        let state = entityState
        let accent = accentColor(for: state)

        return Button {
            Task { await viewModel.executePrimaryAction(for: card) }
        } label: {
            cardContainer(accent: accent, minHeight: 176) {
                if card.isVerticalLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "rectangle.grid.1x2.fill"))
                            Spacer()
                            statusDot(isActive: state?.isActive == true)
                        }

                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Spacer(minLength: 0)

                        Text(state?.displayState ?? "Unavailable")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                } else {
                    HStack(spacing: 18) {
                        iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "rectangle.grid.1x2.fill"))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(primaryTitle(for: state))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)

                            if let subtitle = secondaryTitle(for: state) {
                                Text(subtitle)
                                    .font(.headline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            Text(state?.displayState ?? "Unavailable")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            statusDot(isActive: state?.isActive == true)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var buttonCard: some View {
        let state = entityState
        let accent = accentColor(for: state)
        let navigationPath = card.navigationPath

        return Button {
            Task { await viewModel.executePrimaryAction(for: card) }
        } label: {
            cardContainer(accent: accent, minHeight: 200) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "arrow.right.circle.fill"))
                        Spacer()
                        if navigationPath != nil {
                            Image(systemName: "arrow.right")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Text(primaryTitle(for: state))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text(navigationPath == nil ? (state?.displayState ?? "Run") : "Open section")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var customButtonCard: some View {
        if card.primaryAction != nil {
            return AnyView(buttonCard)
        }

        let accent = Color.white
        let label = resolvedText(card.secondaryText)

        return AnyView(
            cardContainer(accent: accent, minHeight: 220) {
                VStack(alignment: .leading, spacing: 18) {
                    iconBadge(symbolName: symbolName(for: nil, rawIcon: card.icon, fallback: "text.rectangle.fill"))

                    Text(primaryTitle(for: nil))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    if let label {
                        Text(label)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        )
    }

    private var sensorTrendCard: some View {
        let entityID = card.entities.first?.entityID ?? card.entityID
        let state = viewModel.state(for: entityID)
        let accent = accentColor(for: state)
        let history = entityID.map { viewModel.historySamples(for: $0, hours: card.miniGraphHoursToShow) } ?? []
        let minValue = history.map(\.value).min()
        let maxValue = history.map(\.value).max()

        return cardContainer(accent: accent, minHeight: 260) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text("Last \(card.miniGraphHoursToShow)h")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()

                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "chart.line.uptrend.xyaxis"))
                }

                Text(state?.displayState ?? "Unavailable")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if history.count > 1 {
                    DashboardTrendChart(samples: history, accent: accent)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 120)
                        .overlay {
                            Text("Loading trend…")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                }

                HStack(spacing: 12) {
                    if let minValue {
                        DashboardMetricPill(
                            icon: "arrow.down",
                            title: "Min",
                            value: minValue.formatted(.number.precision(.fractionLength(0...1))),
                            tint: accent
                        )
                    }

                    if let maxValue {
                        DashboardMetricPill(
                            icon: "arrow.up",
                            title: "Max",
                            value: maxValue.formatted(.number.precision(.fractionLength(0...1))),
                            tint: accent
                        )
                    }
                }
            }
        }
        .task(id: historyTaskKey(entityID: entityID)) {
            guard let entityID else { return }
            await viewModel.loadHistoryIfNeeded(for: entityID, hours: card.miniGraphHoursToShow)
        }
    }

    private var mediaControlCard: some View {
        let state = entityState
        let accent = accentColor(for: state)

        return cardContainer(accent: accent, minHeight: 260) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state?.mediaTitle ?? primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        if let subtitle = state?.mediaSubtitle ?? state?.appName ?? state?.subtitle {
                            Text(subtitle)
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "play.tv.fill"))
                }

                HStack(spacing: 12) {
                    DashboardMetricPill(
                        icon: state?.state.lowercased() == "playing" ? "waveform" : "pause.fill",
                        title: "Status",
                        value: state?.state.replacingOccurrences(of: "_", with: " ").capitalized ?? "Idle",
                        tint: accent
                    )

                    if let volume = state?.volumePercent {
                        DashboardMetricPill(
                            icon: "speaker.wave.2.fill",
                            title: "Volume",
                            value: "\(volume)%",
                            tint: accent
                        )
                    }
                }

                Spacer(minLength: 0)

                DashboardControlButton(
                    title: state?.state.lowercased() == "playing" ? "Pause" : "Play",
                    systemImage: state?.state.lowercased() == "playing" ? "pause.fill" : "play.fill",
                    tint: accent
                ) {
                    guard let entityID = card.entityID else { return }
                    Task { await viewModel.toggleMediaPlayback(for: entityID) }
                }
            }
        }
    }

    private var thermostatCard: some View {
        let state = entityState
        let accent = accentColor(for: state)
        let current = state?.currentTemperature
        let target = state?.targetTemperature

        return cardContainer(accent: accent, minHeight: 280) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        if let subtitle = secondaryTitle(for: state) {
                            Text(subtitle)
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "thermometer.medium"))
                }

                HStack(spacing: 16) {
                    DashboardMetricPill(
                        icon: "thermometer.medium",
                        title: "Current",
                        value: current.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))°" } ?? "—",
                        tint: accent
                    )

                    DashboardMetricPill(
                        icon: "target",
                        title: "Target",
                        value: target.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))°" } ?? "—",
                        tint: accent
                    )

                    if let eco = card.thermostatEcoTemperature {
                        DashboardMetricPill(
                            icon: "leaf.fill",
                            title: "Eco",
                            value: "\(eco.formatted(.number.precision(.fractionLength(0...1))))°",
                            tint: accent
                        )
                    }
                }

                if let humidity = state?.humidity {
                    Text("Humidity \(humidity)%")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                HStack(spacing: 14) {
                    DashboardControlButton(title: "Cooler", systemImage: "minus", tint: accent) {
                        guard let entityID = card.entityID else { return }
                        Task { await viewModel.adjustClimateTemperature(for: entityID, delta: -0.5) }
                    }

                    DashboardControlButton(title: "Warmer", systemImage: "plus", tint: accent) {
                        guard let entityID = card.entityID else { return }
                        Task { await viewModel.adjustClimateTemperature(for: entityID, delta: 0.5) }
                    }
                }
            }
        }
    }

    private var mushroomLightCard: some View {
        let state = entityState
        let accent = accentColor(for: state)

        return cardContainer(accent: accent, minHeight: 260) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text(state?.displayState ?? "Unavailable")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "lightbulb.fill"))
                }

                HStack(spacing: 12) {
                    DashboardMetricPill(
                        icon: "sun.max.fill",
                        title: "Brightness",
                        value: state?.brightnessPercent.map { "\($0)%" } ?? "—",
                        tint: accent
                    )

                    if card.showsColorTemperatureControl {
                        DashboardMetricPill(
                            icon: "thermometer.sun.fill",
                            title: "Color",
                            value: "Available",
                            tint: accent
                        )
                    }
                }

                HStack(spacing: 14) {
                    DashboardControlButton(
                        title: state?.isActive == true ? "Turn Off" : "Turn On",
                        systemImage: state?.isActive == true ? "lightbulb.slash.fill" : "lightbulb.fill",
                        tint: accent
                    ) {
                        guard let entityID = card.entityID else { return }
                        Task { await viewModel.toggleEntity(entityID) }
                    }

                    if card.showsBrightnessControl {
                        DashboardControlButton(title: "Dim", systemImage: "minus", tint: accent) {
                            guard let entityID = card.entityID else { return }
                            Task { await viewModel.adjustLightBrightness(for: entityID, deltaPercent: -15) }
                        }

                        DashboardControlButton(title: "Brighten", systemImage: "plus", tint: accent) {
                            guard let entityID = card.entityID else { return }
                            Task { await viewModel.adjustLightBrightness(for: entityID, deltaPercent: 15) }
                        }
                    }
                }
            }
        }
    }

    private var mushroomTemplateCard: some View {
        let accent = accentColor(for: entityState)

        return Button {
            Task { await viewModel.executePrimaryAction(for: card) }
        } label: {
            cardContainer(accent: accent, minHeight: 220) {
                VStack(alignment: card.isVerticalLayout ? .leading : .center, spacing: 18) {
                    iconBadge(symbolName: symbolName(for: entityState, rawIcon: card.icon, fallback: "sparkles.rectangle.stack.fill"))

                    Text(primaryTitle(for: entityState))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(card.isVerticalLayout ? .leading : .center)

                    if let subtitle = secondaryTitle(for: entityState) {
                        Text(subtitle)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(card.isVerticalLayout ? .leading : .center)
                    }

                    if card.navigationPath != nil {
                        Label("Open section", systemImage: "arrow.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .frame(maxWidth: .infinity, alignment: card.isVerticalLayout ? .leading : .center)
            }
        }
        .buttonStyle(.plain)
    }

    private var mushroomChipsCard: some View {
        let accent = accentColor(for: entityState)

        return cardContainer(accent: accent, minHeight: 180) {
            VStack(alignment: .leading, spacing: 18) {
                Text(primaryTitle(for: nil))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(card.heading == nil && card.title == nil ? 0 : 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(card.chips) { chip in
                            chipView(chip)
                        }
                    }
                }
            }
        }
    }

    private var roomSummaryCard: some View {
        let accent = Color.cyan
        let activeLights = card.roomLights.compactMap(viewModel.state).filter(\.isActive).count
        let roomSensors = card.roomSensors.compactMap(viewModel.state)
        let topEntities = Array(card.entities.prefix(3))

        return cardContainer(accent: accent, minHeight: 320) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.roomAreaName ?? primaryTitle(for: nil))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if let navigationPath = card.navigationPath {
                            Text(navigationPath.replacingOccurrences(of: "/", with: " • ").trimmingCharacters(in: CharacterSet(charactersIn: " •")))
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: nil, rawIcon: card.icon, fallback: "house.fill"))
                }

                HStack(spacing: 12) {
                    DashboardMetricPill(
                        icon: "lightbulb.max.fill",
                        title: "Lights On",
                        value: "\(activeLights)",
                        tint: accent
                    )

                    ForEach(Array(roomSensors.prefix(2)), id: \.entityID) { sensor in
                        DashboardMetricPill(
                            icon: sensor.iconName,
                            title: sensor.friendlyName,
                            value: sensor.displayState,
                            tint: accent
                        )
                    }
                }

                VStack(spacing: 12) {
                    ForEach(topEntities, id: \.entityID) { item in
                        Button {
                            Task { await viewModel.executePrimaryAction(for: item) }
                        } label: {
                            entityRow(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if card.primaryAction != nil {
                    DashboardControlButton(title: "Open room", systemImage: "arrow.right", tint: accent) {
                        Task { await viewModel.executePrimaryAction(for: card) }
                    }
                }
            }
        }
    }

    private func chipView(_ chip: HAChipItem) -> some View {
        let state = viewModel.state(for: chip.entityID)
        let label = chipLabel(for: chip, state: state)
        let actionItem = chip.entityID.map { HAEntityItem(entityID: $0, name: nil, icon: chip.icon, action: chip.action) }
        let symbol = symbolName(for: state, rawIcon: chip.icon, fallback: chip.type == "weather" ? "cloud.sun.fill" : "circle.fill")

        return Group {
            if let actionItem {
                Button {
                    Task { await viewModel.executePrimaryAction(for: actionItem) }
                } label: {
                    DashboardChipPill(symbolName: symbol, text: label, tint: accentColor(for: state))
                }
                .buttonStyle(.plain)
            } else {
                DashboardChipPill(symbolName: symbol, text: label, tint: accentColor(for: state))
            }
        }
    }

    private func chipLabel(for chip: HAChipItem, state: HAEntityState?) -> String {
        if let resolved = resolvedText(chip.content) {
            return resolved
        }

        if chip.type == "weather" {
            let parts = [
                chip.showTemperature ? state?.displayState : nil,
                chip.showConditions ? state?.subtitle : nil
            ].compactMap { $0 }

            if !parts.isEmpty {
                return parts.joined(separator: " • ")
            }
        }

        if let state {
            return state.displayState
        }

        return "Status"
    }

    private func entityRow(for item: HAEntityItem) -> some View {
        let state = viewModel.state(for: item.entityID)

        return HStack(spacing: 16) {
            Image(systemName: symbolName(for: state, rawIcon: item.icon, fallback: "circle.fill"))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name ?? state?.friendlyName ?? item.entityID)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                if let subtitle = state?.subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            Spacer()

            Text(state?.displayState ?? "Unavailable")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.78))
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func iconBadge(symbolName: String) -> some View {
        Image(systemName: symbolName)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func cardContainer<Content: View>(
        accent: Color,
        minHeight: CGFloat = 220,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.16))
            )
    }

    private func primaryTitle(for state: HAEntityState?) -> String {
        resolvedText(card.primaryText)
            ?? resolvedText(card.heading)
            ?? state?.friendlyName
            ?? "Card"
    }

    private func secondaryTitle(for state: HAEntityState?) -> String? {
        resolvedText(card.secondaryText)
            ?? state?.subtitle
    }

    private func resolvedText(_ value: String?) -> String? {
        guard var text = value?.replacingOccurrences(of: "<br>", with: "\n"),
              !text.isEmpty else {
            return nil
        }

        if let regex = templateStateRegex {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

            for match in matches.reversed() {
                guard match.numberOfRanges > 1 else { continue }
                let entityID = nsText.substring(with: match.range(at: 1))
                let replacement = viewModel.state(for: entityID)?.state ?? "—"

                guard let range = Range(match.range, in: text) else { continue }
                text.replaceSubrange(range, with: replacement)
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("{{") || trimmed.contains("{%") {
            return nil
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    private func accentColor(for state: HAEntityState?) -> Color {
        switch card.type {
        case "custom:better-thermostat-ui-card":
            return .orange
        case "custom:mushroom-light-card":
            return .yellow
        case "custom:mushroom-chips-card":
            return .teal
        case "custom:mushroom-template-card":
            return .blue
        case "custom:mini-graph-card", "sensor":
            return .mint
        case "media-control":
            return .pink
        case "picture-entity", "picture-glance":
            return .cyan
        default:
            break
        }

        switch state?.domain {
        case "camera":
            return .cyan
        case "climate":
            return .orange
        case "light":
            return .yellow
        case "media_player":
            return .pink
        case "sensor":
            return .mint
        case "weather":
            return .blue
        default:
            return .white
        }
    }

    private func symbolName(for state: HAEntityState?, rawIcon: String?, fallback: String) -> String {
        if let state {
            return state.iconName
        }

        if let rawIcon = rawIcon?.lowercased() {
            for (needle, symbol) in mdiSymbolMap where rawIcon.contains(needle) {
                return symbol
            }
        }

        return fallback
    }

    private func statusDot(isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.green : Color.white.opacity(0.34))
            .frame(width: 14, height: 14)
    }

    private func historyTaskKey(entityID: String?) -> String {
        "\(entityID ?? "missing")|\(card.miniGraphHoursToShow)"
    }

    private var entityState: HAEntityState? {
        viewModel.state(for: card.entityID)
    }
}

struct DashboardCameraTile: View {
    let title: String
    let subtitle: String
    let detail: String
    let previewURL: URL?
    var badgeText: String = "LIVE"
    var tint: Color = .cyan
    var isDimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                if let previewURL {
                    AsyncImage(url: previewURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .overlay(ProgressView().tint(.white))
                    }
                } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .overlay {
                                Image(systemName: "video.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if isDimmed {
                    Rectangle()
                        .fill(Color.black.opacity(0.32))
                }

                VStack {
                    HStack {
                        Spacer()

                        HStack(spacing: 8) {
                            Circle()
                                .fill(tint)
                                .frame(width: 8, height: 8)

                            Text(badgeText)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Spacer()
                }
                .padding(14)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))

                    Label(detail, systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, minHeight: 208)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardMetricPill: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DashboardControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardChipPill: View {
    let symbolName: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        )
    }
}

private struct DashboardTrendChart: View {
    let samples: [HAHistorySample]
    let accent: Color

    private var displaySamples: [HAHistorySample] {
        guard samples.count > 60 else { return samples }
        let strideSize = max(samples.count / 60, 1)
        return samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: strideSize) || index == samples.count - 1 ? sample : nil
        }
    }

    var body: some View {
        Chart {
            ForEach(displaySamples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.30), accent.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 120)
    }
}
