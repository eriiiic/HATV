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
        case "weather-forecast":
            weatherForecastCard
        case "custom:hourly-weather":
            hourlyWeatherCard
        case "tile":
            tileCard
        case "button":
            buttonCard
        case "sensor", "custom:mini-graph-card":
            sensorTrendCard
        case "energy-usage-graph":
            energyUsageGraphCard
        case "gauge":
            gaugeCard
        case "media-control":
            mediaControlCard
        case "logbook":
            logbookCard
        case "custom:horizon-card":
            horizonCard
        case "custom:meteoalarm-card":
            meteoAlarmCard
        case "custom:weather-chart-card":
            weatherChartCard
        case "custom:weather-radar-card":
            weatherRadarCard
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
        let referencedStates = card.referencedEntityIDs
            .compactMap(viewModel.state)
            .prefix(3)

        return Button {
            Task { await viewModel.executePrimaryAction(for: card) }
        } label: {
            cardContainer(accent: accent, minHeight: referencedStates.isEmpty ? 168 : 204) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        typeBadge(card.type, tint: accent)
                        Spacer()
                        iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "square.grid.2x2.fill"))
                    }

                    Text(primaryTitle(for: state))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    if let subtitle = secondaryTitle(for: state) {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                    }

                    if !referencedStates.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(Array(referencedStates), id: \.entityID) { referencedState in
                                compactEntitySummaryRow(for: referencedState)
                            }
                        }
                    } else if let state {
                        DashboardMetricPill(
                            icon: state.iconName,
                            title: state.friendlyName,
                            value: state.displayState,
                            tint: accent
                        )
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var headingCard: some View {
        let accent = accentColor(for: nil)

        return cardContainer(accent: accent, minHeight: 90) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    iconBadge(symbolName: symbolName(for: nil, rawIcon: card.icon, fallback: "sparkles"))
                    Text(primaryTitle(for: nil))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                }

                if let subtitle = secondaryTitle(for: nil) {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(2)
                }
            }
        }
    }

    private var entitiesCard: some View {
        let accent = accentColor(for: entityState)

        return cardContainer(accent: accent, minHeight: 220) {
            VStack(alignment: .leading, spacing: 14) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                VStack(spacing: 10) {
                    ForEach(card.entities, id: \.entityID) { item in
                        Button {
                            Task { await viewModel.executePrimaryAction(for: item) }
                        } label: {
                            entityRow(for: item)
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
                .focusSection()
            }
        }
    }

    private var glanceCard: some View {
        let accent = accentColor(for: entityState)

        return cardContainer(accent: accent, minHeight: 210) {
            VStack(alignment: .leading, spacing: 14) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                responsiveInteractiveGrid(maxColumns: 3) {
                    ForEach(card.entities, id: \.entityID) { item in
                        let state = viewModel.state(for: item.entityID)

                        Button {
                            Task { await viewModel.executePrimaryAction(for: item) }
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: symbolName(for: state, rawIcon: item.icon, fallback: "circle.fill"))
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)

                                Text(item.name ?? state?.friendlyName ?? item.entityID)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.78)

                                Text(state?.displayState ?? "Unknown")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(state?.isActive == true ? .green : .white.opacity(0.72))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 124)
                            .padding(12)
                            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                    }
                }
            }
        }
    }

    private var nestedGridCard: some View {
        let accent = accentColor(for: entityState)
        let visibleChildCards = card.childCards.filter(viewModel.shouldDisplayCard)

        return cardContainer(accent: accent, minHeight: 220) {
            VStack(alignment: .leading, spacing: 18) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: min(max(card.columns, 1), 2)),
                    spacing: 18
                ) {
                    ForEach(visibleChildCards) { child in
                        embeddedCardView(for: child)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stackCard(axis: Axis) -> some View {
        let accent = accentColor(for: entityState)
        let visibleChildCards = card.childCards.filter(viewModel.shouldDisplayCard)

        cardContainer(accent: accent, minHeight: 196) {
            VStack(alignment: .leading, spacing: 18) {
                if let title = resolvedText(card.heading) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                if axis == .horizontal {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(visibleChildCards) { child in
                                embeddedCardView(for: child)
                            }
                        }

                        VStack(spacing: 12) {
                            ForEach(visibleChildCards) { child in
                                embeddedCardView(for: child)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(visibleChildCards) { child in
                            embeddedCardView(for: child)
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
            previewURL: previewURL,
            fitMode: card.fitMode,
            style: .dashboard
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
            cardContainer(accent: accent, minHeight: card.isVerticalLayout ? 188 : 152) {
                ViewThatFits(in: .horizontal) {
                    tileHorizontalLayout(state: state)
                    tileVerticalLayout(state: state)
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
            cardContainer(accent: accent, minHeight: 148) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        if card.buttonShowsIcon {
                            iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "arrow.right.circle.fill"))
                        }

                        Spacer()

                        if navigationPath != nil {
                            Image(systemName: "arrow.right")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }

                    if card.buttonShowsName {
                        Text(primaryTitle(for: state))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }

                    Text(card.buttonShowsState ? (state?.displayState ?? "Unavailable") : (navigationPath == nil ? "Tap to run" : "Open section"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(2)
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
            cardContainer(accent: accent, minHeight: 180) {
                VStack(alignment: .leading, spacing: 14) {
                    iconBadge(symbolName: symbolName(for: nil, rawIcon: card.icon, fallback: "text.rectangle.fill"))

                    Text(primaryTitle(for: nil))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    if let label {
                        Text(label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                }
            }
        )
    }

    private var weatherForecastCard: some View {
        let entityID = card.entityID ?? ""
        let state = viewModel.state(for: entityID)
        let accent = Color.blue
        let forecastType = card.weatherForecastType
        let forecasts = Array(viewModel.weatherForecast(for: entityID, type: forecastType).prefix(card.weatherShowForecast ? 5 : 0))
        let currentTemperature = state?.weatherTemperature ?? forecasts.first?.temperature

        return cardContainer(accent: accent, minHeight: card.weatherShowForecast ? 216 : 184) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        typeBadge("weather", tint: accent)

                        Text(primaryTitle(for: state))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        if let subtitle = state?.subtitle {
                            Text(subtitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .trailing, spacing: 4) {
                            if let currentTemperature {
                                Text(formatTemperature(currentTemperature, round: card.weatherRoundTemperature, unit: state?.temperatureUnit ?? "°"))
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }

                            Text(weatherSecondaryText(state: state, forecasts: forecasts))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }

                        Image(systemName: weatherSymbolName(condition: state?.state ?? forecasts.first?.condition))
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }

                if card.weatherShowForecast, !forecasts.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            ForEach(forecasts) { forecast in
                                WeatherForecastPill(
                                    forecast: forecast,
                                    type: forecastType,
                                    roundTemperature: card.weatherRoundTemperature,
                                    temperatureUnit: state?.temperatureUnit ?? "°"
                                )
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(forecasts) { forecast in
                                WeatherForecastPill(
                                    forecast: forecast,
                                    type: forecastType,
                                    roundTemperature: card.weatherRoundTemperature,
                                    temperatureUnit: state?.temperatureUnit ?? "°"
                                )
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(entityID)|\(forecastType.rawValue)") {
            guard !entityID.isEmpty else { return }
            await viewModel.loadWeatherForecastIfNeeded(for: entityID, type: forecastType)
        }
    }

    private var hourlyWeatherCard: some View {
        let entityID = card.entityID ?? ""
        let state = viewModel.state(for: entityID)
        let accent = Color.cyan
        let forecasts = Array(viewModel.weatherForecast(for: entityID, type: .hourly).prefix(8))

        return cardContainer(accent: accent, minHeight: 212) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(primaryTitle(for: state))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(state?.subtitle ?? "Hourly weather")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(state?.displayState ?? "—")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if let windSpeed = state?.windSpeed {
                            Text("Wind \(windSpeed.formatted(.number.precision(.fractionLength(0...1)))) \(state?.windSpeedUnit ?? "")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.66))
                        }
                    }
                }

                if forecasts.isEmpty {
                    emptyInlineState(text: "Loading hourly forecast…", icon: "cloud.sun.fill")
                } else {
                    HStack(spacing: 10) {
                        ForEach(forecasts) { forecast in
                            HourlyWeatherCell(
                                forecast: forecast,
                                showsDate: card.hourlyWeatherShowsDate,
                                showsWind: card.hourlyWeatherWindStyle != nil,
                                showsPrecipitationProbability: card.hourlyWeatherShowsPrecipitationProbability,
                                showsPrecipitationAmounts: card.hourlyWeatherShowsPrecipitationAmounts,
                                temperatureUnit: state?.temperatureUnit ?? "°",
                                precipitationUnit: state?.precipitationUnit ?? "mm"
                            )
                        }
                    }
                }
            }
        }
        .task(id: "\(entityID)|hourly-native") {
            guard !entityID.isEmpty else { return }
            await viewModel.loadWeatherForecastIfNeeded(for: entityID, type: .hourly)
        }
    }

    private var logbookCard: some View {
        let accent = Color.orange
        let entries = Array(viewModel.logbookEntries(for: card).prefix(6))

        return cardContainer(accent: accent, minHeight: 220) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title ?? "Activity")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text("Last \(card.miniGraphHoursToShow) hours")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()
                    iconBadge(symbolName: "clock.arrow.circlepath")
                }

                if entries.isEmpty {
                    emptyInlineState(text: "No recent activity in this time range.", icon: "clock.badge.xmark")
                } else {
                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            LogbookEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .task(id: "\(card.id)|logbook") {
            await viewModel.loadLogbookIfNeeded(
                entityIDs: card.logbookEntityIDs,
                hours: card.miniGraphHoursToShow,
                stateFilter: card.logbookStateFilter
            )
        }
    }

    private var horizonCard: some View {
        let sunState = viewModel.state(for: "sun.sun")
        let accent = Color.yellow
        let nextRising = dateAttribute(named: "next_rising", from: sunState)
        let nextSetting = dateAttribute(named: "next_setting", from: sunState)
        let azimuth = sunState?.attributes["azimuth"]?.lossyDoubleValue
        let elevation = sunState?.attributes["elevation"]?.lossyDoubleValue

        return cardContainer(accent: accent, minHeight: 192) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sun")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(sunState?.formattedStateDescription ?? "Tracking")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()
                    iconBadge(symbolName: "sun.max.fill")
                }

                adaptiveMetricGrid {
                    if card.horizonShowsSunrise, let nextRising {
                        DashboardMetricPill(
                            icon: "sunrise.fill",
                            title: "Sunrise",
                            value: nextRising.formatted(.dateTime.hour().minute()),
                            tint: accent
                        )
                    }

                    if card.horizonShowsSunset, let nextSetting {
                        DashboardMetricPill(
                            icon: "sunset.fill",
                            title: "Sunset",
                            value: nextSetting.formatted(.dateTime.hour().minute()),
                            tint: accent
                        )
                    }

                    if card.horizonShowsAzimuth, let azimuth {
                        DashboardMetricPill(
                            icon: "location.north.line.fill",
                            title: "Azimuth",
                            value: "\(azimuth.formatted(.number.precision(.fractionLength(0))))°",
                            tint: accent
                        )
                    }

                    if card.horizonShowsElevation, let elevation {
                        DashboardMetricPill(
                            icon: "sun.horizon.fill",
                            title: "Elevation",
                            value: "\(elevation.formatted(.number.precision(.fractionLength(0...1))))°",
                            tint: accent
                        )
                    }
                }
            }
        }
    }

    private var meteoAlarmCard: some View {
        let alertState = viewModel.state(for: card.alertEntityIDs.first)
        let accent = alertTint(for: alertState?.state)
        let activeAlerts = alertAttributes(from: alertState)

        return cardContainer(accent: accent, minHeight: 196) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Weather Alert")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(alertState?.state ?? "Unavailable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()
                    iconBadge(symbolName: "exclamationmark.triangle.fill")
                }

                if activeAlerts.isEmpty {
                    emptyInlineState(text: "No active weather warnings right now.", icon: "checkmark.shield.fill")
                } else {
                    adaptiveMetricGrid {
                        ForEach(activeAlerts, id: \.title) { alert in
                            DashboardMetricPill(
                                icon: "flag.fill",
                                title: alert.title,
                                value: alert.value,
                                tint: alertTint(for: alert.value)
                            )
                        }
                    }
                }
            }
        }
    }

    private var weatherChartCard: some View {
        let entityID = card.entityID ?? ""
        let state = viewModel.state(for: entityID)
        let accent = Color.blue
        let forecastType = card.weatherChartForecastType
        let desiredForecastCount = max(card.weatherChartForecastCount, 6)
        let forecasts = Array(viewModel.weatherForecast(for: entityID, type: forecastType).prefix(desiredForecastCount))
        let chartSamples = forecasts.enumerated().compactMap { index, forecast -> WeatherChartSample? in
            guard let date = forecast.date, let temperature = forecast.temperature else {
                return nil
            }

            return WeatherChartSample(
                id: "\(index)-\(forecast.id)",
                date: date,
                temperature: temperature,
                precipitationProbability: forecast.precipitationProbability,
                precipitationAmount: forecast.precipitation
            )
        }

        return cardContainer(accent: accent, minHeight: 272) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(primaryTitle(for: state))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(card.weatherChartShowsCurrentCondition ? (state?.subtitle ?? "Forecast") : "Forecast")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(state?.displayState ?? "—")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if card.weatherChartShowsLastChanged, let updatedAt = state?.lastUpdatedDate {
                            Text("Updated \(updatedAt, format: .relative(presentation: .named))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                }

                if chartSamples.count > 1 {
                    NativeWeatherTrendChart(samples: chartSamples, accent: accent)
                } else {
                    emptyInlineState(text: "Loading forecast curve…", icon: "chart.line.uptrend.xyaxis")
                }

                adaptiveMetricGrid {
                    if card.weatherChartShowsHumidity, let humidity = state?.humidity {
                        DashboardMetricPill(
                            icon: "humidity.fill",
                            title: "Humidity",
                            value: "\(humidity)%",
                            tint: accent
                        )
                    }

                    if card.weatherChartShowsPressure, let pressure = state?.pressure {
                        DashboardMetricPill(
                            icon: "gauge.medium",
                            title: "Pressure",
                            value: "\(pressure.formatted(.number.precision(.fractionLength(0...1)))) \(state?.pressureUnit ?? "")",
                            tint: accent
                        )
                    }

                    if card.weatherChartShowsWindSpeed, let windSpeed = state?.windSpeed {
                        DashboardMetricPill(
                            icon: "wind",
                            title: "Wind",
                            value: "\(windSpeed.formatted(.number.precision(.fractionLength(0...1)))) \(state?.windSpeedUnit ?? "")",
                            tint: accent
                        )
                    }

                    if card.weatherChartShowsWindDirection, let windBearing = state?.windBearing {
                        DashboardMetricPill(
                            icon: "location.north.line.fill",
                            title: "Bearing",
                            value: "\(windBearing.formatted(.number.precision(.fractionLength(0))))°",
                            tint: accent
                        )
                    }
                }
            }
        }
        .task(id: "\(entityID)|\(forecastType.rawValue)|weather-chart") {
            guard !entityID.isEmpty else { return }
            await viewModel.loadWeatherForecastIfNeeded(for: entityID, type: forecastType)
        }
    }

    private var weatherRadarCard: some View {
        let entityID = viewModel.preferredWeatherEntityID ?? ""
        let state = viewModel.state(for: entityID)
        let accent = Color.cyan
        let forecasts = Array(viewModel.weatherForecast(for: entityID, type: .hourly).prefix(10))
        let chartSamples = forecasts.enumerated().compactMap { index, forecast -> WeatherRadarSample? in
            guard let date = forecast.date else {
                return nil
            }

            let probability = Double(forecast.precipitationProbability ?? 0)
            let amount = forecast.precipitation ?? 0
            guard probability > 0 || amount > 0 else {
                return nil
            }

            return WeatherRadarSample(
                id: "\(index)-\(forecast.id)",
                date: date,
                precipitationProbability: probability,
                precipitationAmount: amount
            )
        }

        return cardContainer(accent: accent, minHeight: 240) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rain Outlook")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(state?.friendlyName ?? "Hourly precipitation")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Spacer()
                    iconBadge(symbolName: "cloud.rain.fill")
                }

                if chartSamples.isEmpty {
                    emptyInlineState(text: "No rain expected in the next few hours.", icon: "sun.max.fill")
                } else {
                    NativeWeatherRadarChart(
                        samples: chartSamples,
                        accent: accent,
                        precipitationUnit: state?.precipitationUnit ?? "mm"
                    )
                }
            }
        }
        .task(id: "\(entityID)|weather-radar") {
            guard !entityID.isEmpty else { return }
            await viewModel.loadWeatherForecastIfNeeded(for: entityID, type: .hourly)
        }
    }

    private var gaugeCard: some View {
        let state = entityState
        let accent = accentColor(for: state)
        let currentValue = state?.numericState ?? 0
        let minimum = card.gaugeMinValue
        let maximum = max(card.gaugeMaxValue, minimum + 1)
        let tint = gaugeColor(for: currentValue)

        return cardContainer(accent: accent, minHeight: 196) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let subtitle = secondaryTitle(for: state) {
                            Text(subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(2)
                        }

                        DashboardMetricPill(
                            icon: state?.iconName ?? "gauge.with.dots.needle.50percent",
                            title: "Range",
                            value: "\(formatGaugeValue(minimum, state: state)) - \(formatGaugeValue(maximum, state: state))",
                            tint: tint
                        )
                    }

                    Spacer()

                    GaugeRingView(
                        progress: gaugeProgress(for: currentValue, min: minimum, max: maximum),
                        tint: tint,
                        valueText: state?.displayState ?? formatGaugeValue(currentValue, state: state),
                        subtitle: card.gaugeUsesNeedle ? "Needle" : "Gauge"
                    )
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Spacer()
                    }

                    GaugeRingView(
                        progress: gaugeProgress(for: currentValue, min: minimum, max: maximum),
                        tint: tint,
                        valueText: state?.displayState ?? formatGaugeValue(currentValue, state: state),
                        subtitle: "\(formatGaugeValue(minimum, state: state)) - \(formatGaugeValue(maximum, state: state))"
                    )
                }
            }
        }
    }

    private var sensorTrendCard: some View {
        let entityID = card.graphEntityIDs.first
        let state = viewModel.state(for: entityID)
        let accent = accentColor(for: state)
        let history = entityID.map { viewModel.historySamples(for: $0, hours: card.miniGraphHoursToShow) } ?? []
        let minValue = history.map(\.value).min()
        let maxValue = history.map(\.value).max()
        let showsTrend = card.prefersTrendVisualization

        return cardContainer(accent: accent, minHeight: showsTrend ? 224 : 168) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(showsTrend ? "Last \(card.miniGraphHoursToShow)h" : (state?.subtitle ?? "Sensor"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    Spacer()

                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "chart.line.uptrend.xyaxis"))
                }

                Text(state?.displayState ?? "Unavailable")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if showsTrend {
                    if history.count > 1 {
                        DashboardTrendChart(samples: history, accent: accent)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 104)
                            .overlay {
                                Text("Loading trend…")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                    }
                }

                adaptiveMetricGrid {
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
                    
                    if !showsTrend, let state {
                        DashboardMetricPill(
                            icon: state.iconName,
                            title: "State",
                            value: state.formattedStateDescription,
                            tint: accent
                        )
                    }
                }
            }
        }
        .task(id: historyTaskKey(entityID: entityID)) {
            guard showsTrend, let entityID else { return }
            await viewModel.loadHistoryIfNeeded(for: entityID, hours: card.miniGraphHoursToShow)
        }
    }

    private var energyUsageGraphCard: some View {
        let statisticID = viewModel.energyUsageStatisticID
        let state = viewModel.state(for: statisticID)
        let accent = Color.cyan
        let hours = max(card.miniGraphHoursToShow, 24)
        let samples = statisticID.map { viewModel.statisticsSamples(for: $0, hours: hours, period: .hour) } ?? []
        let minValue = samples.map(\.value).min()
        let maxValue = samples.map(\.value).max()
        let currentValue = samples.last?.value

        return cardContainer(accent: accent, minHeight: 240) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text("Hourly average over the last \(hours)h")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    Spacer()

                    iconBadge(symbolName: "bolt.fill")
                }

                Text(state?.displayState ?? currentValue.map(powerValueString) ?? "Unavailable")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if samples.count > 1 {
                    DashboardTrendChart(samples: samples, accent: accent)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 104)
                        .overlay {
                            Text("Loading energy trend…")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                }

                adaptiveMetricGrid {
                    if let minValue {
                        DashboardMetricPill(
                            icon: "arrow.down",
                            title: "Low",
                            value: powerValueString(minValue),
                            tint: accent
                        )
                    }

                    if let maxValue {
                        DashboardMetricPill(
                            icon: "arrow.up",
                            title: "High",
                            value: powerValueString(maxValue),
                            tint: accent
                        )
                    }

                    if let currentValue {
                        DashboardMetricPill(
                            icon: "waveform.path.ecg",
                            title: "Current",
                            value: powerValueString(currentValue),
                            tint: accent
                        )
                    }
                }
            }
        }
        .task(id: "energy-usage|\(hours)") {
            await viewModel.loadEnergyUsageIfNeeded(hours: hours)
        }
    }

    private var mediaControlCard: some View {
        let state = entityState
        let accent = accentColor(for: state)

        return cardContainer(accent: accent, minHeight: 204) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(state?.mediaTitle ?? primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let subtitle = state?.mediaSubtitle ?? state?.appName ?? state?.subtitle {
                            Text(subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "play.tv.fill"))
                }

                adaptiveMetricGrid {
                    DashboardMetricPill(
                        icon: state?.state.lowercased() == "playing" ? "waveform" : "pause.fill",
                        title: "Status",
                        value: state?.formattedStateDescription ?? "Idle",
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

                adaptiveButtonGrid(maxColumns: 1) {
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
    }

    private var thermostatCard: some View {
        let state = entityState
        let accent = accentColor(for: state)
        let current = state?.currentTemperature
        let target = state?.targetTemperature

        return cardContainer(accent: accent, minHeight: 224) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let subtitle = secondaryTitle(for: state) {
                            Text(subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "thermometer.medium"))
                }

                adaptiveMetricGrid {
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                adaptiveButtonGrid(maxColumns: 2) {
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

        return cardContainer(accent: accent, minHeight: 204) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryTitle(for: state))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(state?.displayState ?? "Unavailable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "lightbulb.fill"))
                }

                adaptiveMetricGrid {
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

                Spacer(minLength: 0)

                adaptiveButtonGrid(maxColumns: 3) {
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
            cardContainer(accent: accent, minHeight: 176) {
                VStack(alignment: card.isVerticalLayout ? .leading : .center, spacing: 14) {
                    iconBadge(symbolName: symbolName(for: entityState, rawIcon: card.icon, fallback: "sparkles.rectangle.stack.fill"))

                    Text(primaryTitle(for: entityState))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(card.isVerticalLayout ? .leading : .center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    if let subtitle = secondaryTitle(for: entityState) {
                        Text(subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .multilineTextAlignment(card.isVerticalLayout ? .leading : .center)
                            .lineLimit(3)
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

        return cardContainer(accent: accent, minHeight: 116) {
            VStack(alignment: .leading, spacing: 14) {
                Text(primaryTitle(for: nil))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .opacity(card.heading == nil && card.title == nil ? 0 : 1)

                responsiveInteractiveGrid(maxColumns: 3) {
                    ForEach(card.chips) { chip in
                        chipView(chip)
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

        return cardContainer(accent: accent, minHeight: 244) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.roomAreaName ?? primaryTitle(for: nil))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let navigationPath = card.navigationPath {
                            Text(navigationPath.replacingOccurrences(of: "/", with: " • ").trimmingCharacters(in: CharacterSet(charactersIn: " •")))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                    iconBadge(symbolName: symbolName(for: nil, rawIcon: card.icon, fallback: "house.fill"))
                }

                adaptiveMetricGrid {
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
                        .focusEffectDisabled()
                    }
                }
                .focusSection()

                Spacer(minLength: 0)

                if card.primaryAction != nil {
                    adaptiveButtonGrid(maxColumns: 1) {
                        DashboardControlButton(title: "Open room", systemImage: "arrow.right", tint: accent) {
                            Task { await viewModel.executePrimaryAction(for: card) }
                        }
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
                .focusEffectDisabled()
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

    @ViewBuilder
    private func embeddedCardView(for child: HAAnyConfig) -> some View {
        if child.usesStandaloneFocusSurface {
            DashboardStandaloneFocusCard {
                DashboardCardContent(card: child, viewModel: viewModel, openCamera: openCamera)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            DashboardCardContent(card: child, viewModel: viewModel, openCamera: openCamera)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func entityRow(for item: HAEntityItem) -> some View {
        let state = viewModel.state(for: item.entityID)
        let symbol = symbolName(for: state, rawIcon: item.icon, fallback: "circle.fill")
        let title = item.name ?? state?.friendlyName ?? item.entityID
        let subtitle = state?.subtitle
        let value = state?.displayState ?? "Unavailable"
        let isActive = state?.isActive == true

        return ViewThatFits(in: .horizontal) {
            DashboardEntityRowLabel(
                symbolName: symbol,
                title: title,
                subtitle: subtitle,
                value: value,
                isActive: isActive,
                compact: false
            )

            DashboardEntityRowLabel(
                symbolName: symbol,
                title: title,
                subtitle: subtitle,
                value: value,
                isActive: isActive,
                compact: true
            )
        }
    }

    private func iconBadge(symbolName: String) -> some View {
        Image(systemName: symbolName)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func cardContainer<Content: View>(
        accent: Color,
        minHeight: CGFloat = 220,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.11, blue: 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(accent.opacity(0.08))
            )
    }

    private func tileHorizontalLayout(state: HAEntityState?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "rectangle.grid.1x2.fill"))

            VStack(alignment: .leading, spacing: 8) {
                Text(primaryTitle(for: state))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let subtitle = secondaryTitle(for: state) {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 10) {
                Text(state?.displayState ?? "Unavailable")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                statusDot(isActive: state?.isActive == true)
            }
        }
    }

    private func tileVerticalLayout(state: HAEntityState?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                iconBadge(symbolName: symbolName(for: state, rawIcon: card.icon, fallback: "rectangle.grid.1x2.fill"))
                Spacer()
                statusDot(isActive: state?.isActive == true)
            }

            Text(primaryTitle(for: state))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Text(state?.displayState ?? "Unavailable")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }

    private func compactEntitySummaryRow(for state: HAEntityState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.iconName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(state.friendlyName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(state.displayState)
                .font(.caption.weight(.bold))
                .foregroundStyle(state.isActive ? .green : .white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func adaptiveMetricGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                content()
            }

            LazyVGrid(columns: [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                content()
            }
        }
        .focusSection()
    }

    private func adaptiveButtonGrid<Content: View>(
        maxColumns: Int = 2,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            if maxColumns >= 3 {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    content()
                }
            }

            if maxColumns >= 2 {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    content()
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                content()
            }
        }
        .focusSection()
    }

    private func responsiveInteractiveGrid<Content: View>(
        maxColumns: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            if maxColumns >= 3 {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    content()
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                content()
            }

            LazyVGrid(columns: [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                content()
            }
        }
        .focusSection()
    }

    private func typeBadge(_ value: String, tint: Color) -> some View {
        Text(value.replacingOccurrences(of: "custom:", with: "").replacingOccurrences(of: "-", with: " ").uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func weatherSecondaryText(
        state: HAEntityState?,
        forecasts: [HAWeatherForecastEntry]
    ) -> String {
        if let preferred = card.weatherSecondaryInfoAttribute?.lowercased() {
            switch preferred {
            case "humidity":
                if let humidity = state?.humidity ?? forecasts.first?.humidity {
                    return "Humidity \(humidity)%"
                }
            case "precipitation":
                if let precipitation = forecasts.first?.precipitation {
                    return "Precipitation \(precipitation.formatted(.number.precision(.fractionLength(0...1))))"
                }
            case "extrema":
                if let forecast = forecasts.first,
                   let high = forecast.temperature,
                   let low = forecast.templow {
                    return "High \(formatTemperature(high, round: card.weatherRoundTemperature, unit: state?.temperatureUnit ?? "°")) • Low \(formatTemperature(low, round: card.weatherRoundTemperature, unit: state?.temperatureUnit ?? "°"))"
                }
            default:
                break
            }
        }

        if let forecast = forecasts.first,
           let high = forecast.temperature,
           let low = forecast.templow {
            return "High \(formatTemperature(high, round: card.weatherRoundTemperature, unit: state?.temperatureUnit ?? "°")) • Low \(formatTemperature(low, round: card.weatherRoundTemperature, unit: state?.temperatureUnit ?? "°"))"
        }

        if let precipitation = forecasts.first?.precipitation {
            return "Precipitation \(precipitation.formatted(.number.precision(.fractionLength(0...1))))"
        }

        if let humidity = state?.humidity ?? forecasts.first?.humidity {
            return "Humidity \(humidity)%"
        }

        return state?.formattedStateDescription ?? "Weather"
    }

    private func formatTemperature(_ value: Double, round: Bool, unit: String) -> String {
        let formatted = round
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(formatted)\(unit)"
    }

    private func weatherSymbolName(condition: String?) -> String {
        switch condition?.lowercased() {
        case "clear-night":
            return "moon.stars.fill"
        case "partlycloudy", "partly cloudy":
            return "cloud.sun.fill"
        case "cloudy":
            return "cloud.fill"
        case "rainy", "pouring":
            return "cloud.rain.fill"
        case "snowy", "snowy-rainy":
            return "cloud.snow.fill"
        case "windy", "windy-variant":
            return "wind"
        case "lightning", "lightning-rainy":
            return "cloud.bolt.rain.fill"
        case "fog":
            return "cloud.fog.fill"
        case "sunny":
            return "sun.max.fill"
        default:
            return "cloud.sun.fill"
        }
    }

    private func emptyInlineState(text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dateAttribute(named key: String, from state: HAEntityState?) -> Date? {
        guard let value = state?.attributes[key]?.stringValue else {
            return nil
        }

        return Self.iso8601FractionalDateFormatter.date(from: value)
            ?? Self.iso8601DateFormatter.date(from: value)
    }

    private func alertTint(for value: String?) -> Color {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "green", "vert":
            return .green
        case "yellow", "jaune":
            return .yellow
        case "orange":
            return .orange
        case "red", "rouge":
            return .red
        default:
            return .white
        }
    }

    private func alertAttributes(from state: HAEntityState?) -> [WeatherAlertAttribute] {
        guard let attributes = state?.attributes else {
            return []
        }

        return attributes
            .compactMap { key, value -> WeatherAlertAttribute? in
                guard !["attribution", "icon", "friendly_name"].contains(key),
                      let stringValue = value.stringValue else {
                    return nil
                }

                let normalized = stringValue.lowercased()
                guard normalized != "green", normalized != "vert" else {
                    return nil
                }

                return WeatherAlertAttribute(
                    title: prettifiedIdentifier(key),
                    value: stringValue
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private func gaugeProgress(for value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0 }
        return Swift.min(Swift.max((value - min) / (max - min), 0), 1)
    }

    private func gaugeColor(for value: Double) -> Color {
        let thresholds = gaugeThresholds()
        for (threshold, color) in thresholds where value <= threshold {
            return color
        }
        return thresholds.last?.1 ?? .green
    }

    private func gaugeThresholds() -> [(Double, Color)] {
        let severity = card.raw["severity"]?.objectValue ?? [:]
        let values: [(Double, Color)] = [
            (severity["green"]?.doubleValue ?? .greatestFiniteMagnitude, .green),
            (severity["yellow"]?.doubleValue ?? .greatestFiniteMagnitude, .yellow),
            (severity["red"]?.doubleValue ?? .greatestFiniteMagnitude, .red)
        ]
        let filtered = values.filter { $0.0.isFinite }
        return filtered.isEmpty ? [(card.gaugeMaxValue, .green)] : filtered.sorted { $0.0 < $1.0 }
    }

    private func formatGaugeValue(_ value: Double, state: HAEntityState?) -> String {
        let unit = state?.attributes["unit_of_measurement"]?.stringValue ?? ""
        let formatted = value.formatted(.number.precision(.fractionLength(0...1)))
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    private func powerValueString(_ value: Double) -> String {
        if value >= 1000 {
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) W"
        }

        return "\(value.formatted(.number.precision(.fractionLength(0)))) W"
    }

    private func primaryTitle(for state: HAEntityState?) -> String {
        resolvedText(card.primaryText)
            ?? resolvedText(card.heading)
            ?? card.roomAreaName
            ?? state?.friendlyName
            ?? navigationTitle(from: card.navigationPath)
            ?? cardTypeTitle
    }

    private func secondaryTitle(for state: HAEntityState?) -> String? {
        resolvedText(card.secondaryText)
            ?? state?.subtitle
            ?? navigationSubtitle(from: card.navigationPath)
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
        case "energy-usage-graph":
            return .cyan
        case "media-control":
            return .pink
        case "weather-forecast":
            return .blue
        case "gauge":
            return .mint
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

    private var cardTypeTitle: String {
        prettifiedIdentifier(card.type)
    }

    private func navigationTitle(from path: String?) -> String? {
        let components = navigationComponents(from: path)
        guard let last = components.last else { return nil }
        return prettifiedIdentifier(last)
    }

    private func navigationSubtitle(from path: String?) -> String? {
        let components = navigationComponents(from: path)
        guard components.count > 1 else { return nil }
        return components
            .dropLast()
            .map(prettifiedIdentifier)
            .joined(separator: " • ")
    }

    private func navigationComponents(from path: String?) -> [String] {
        guard let path else { return [] }

        return path
            .split(separator: "?")
            .first?
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }

    private func prettifiedIdentifier(_ rawValue: String) -> String {
        let cleaned = rawValue
            .replacingOccurrences(of: "custom:", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "Card" }

        return cleaned
            .split(separator: " ")
            .map { token in
                let lowercased = token.lowercased()
                if lowercased.count <= 3 {
                    return lowercased.uppercased()
                }
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
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

    private static let iso8601FractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum DashboardCameraTileStyle: Sendable {
    case videoWall
    case dashboard
}

struct DashboardStandaloneFocusCard<Content: View>: View {
    @Environment(\.isFocused) private var isFocused

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isFocused ? 1.008 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(isFocused ? 0.18 : 0), lineWidth: 2)
            }
            .shadow(color: .black.opacity(isFocused ? 0.14 : 0), radius: isFocused ? 16 : 0, y: 8)
            .focusable(true)
            .focusEffectDisabled()
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

struct DashboardCameraTile: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let subtitle: String
    let detail: String
    let previewURL: URL?
    var fitMode: String? = nil
    var badgeText: String = "LIVE"
    var tint: Color = .cyan
    var isDimmed = false
    var style: DashboardCameraTileStyle = .videoWall
    var height: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                cameraPreview

                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if isDimmed {
                    Rectangle()
                        .fill(Color.black.opacity(0.34))
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
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    Spacer()
                }
                .padding(16)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: style == .videoWall ? 22 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)

                    Label(detail, systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(style == .videoWall ? 16 : 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height ?? tileHeight)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.10, blue: 0.14))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(isFocused ? 0.30 : 0.12), lineWidth: isFocused ? 2 : 1)
            )
            .shadow(color: .black.opacity(isFocused ? 0.10 : 0.04), radius: isFocused ? 10 : 4, y: 4)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var cameraPreview: some View {
        Group {
            if let previewURL {
                AsyncImage(url: previewURL) { image in
                    image.resizable()
                        .modifier(CameraPreviewScaleModifier(usesCoverMode: usesCoverMode))
                } placeholder: {
                    placeholderPreview
                }
            } else {
                placeholderPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholderPreview: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .overlay {
                Image(systemName: "video.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
    }

    private var usesCoverMode: Bool {
        fitMode?.lowercased() != "contain"
    }

    private var tileHeight: CGFloat {
        switch style {
        case .videoWall:
            return 204
        case .dashboard:
            return 178
        }
    }

    private var cornerRadius: CGFloat {
        style == .videoWall ? 12 : 10
    }
}

private struct CameraPreviewScaleModifier: ViewModifier {
    let usesCoverMode: Bool

    func body(content: Content) -> some View {
        if usesCoverMode {
            AnyView(content.scaledToFill())
        } else {
            AnyView(content.scaledToFit())
        }
    }
}

private struct DashboardEntityRowLabel: View {
    @Environment(\.isFocused) private var isFocused

    let symbolName: String
    let title: String
    let subtitle: String?
    let value: String
    let isActive: Bool
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                compactLayout
            } else {
                horizontalLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 14) {
            iconView

            VStack(alignment: .leading, spacing: 4) {
                titleView

                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            valueView(lineLimit: 1)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                iconView
                titleView
            }

            valueView(lineLimit: 2)
        }
    }

    private var iconView: some View {
        Image(systemName: symbolName)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Color.white.opacity(isFocused ? 0.12 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var titleView: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private func valueView(lineLimit: Int) -> some View {
        Text(value)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isActive ? .green : .white.opacity(0.78))
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.7)
    }

    private var backgroundColor: Color {
        isFocused ? Color.white.opacity(0.12) : Color.white.opacity(0.045)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.24) : .white.opacity(0.06)
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
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DashboardControlButton: View {
    @Environment(\.isFocused) private var isFocused

    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .frame(width: 18)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var backgroundColor: Color {
        isFocused ? tint.opacity(0.24) : tint.opacity(0.12)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.26) : .white.opacity(0.08)
    }
}

private struct DashboardChipPill: View {
    @Environment(\.isFocused) private var isFocused

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
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }

    private var backgroundColor: Color {
        isFocused ? tint.opacity(0.24) : tint.opacity(0.14)
    }

    private var borderColor: Color {
        isFocused ? .white.opacity(0.28) : .white.opacity(0.10)
    }
}

private struct WeatherAlertAttribute {
    let title: String
    let value: String
}

private struct HourlyWeatherCell: View {
    let forecast: HAWeatherForecastEntry
    let showsDate: Bool
    let showsWind: Bool
    let showsPrecipitationProbability: Bool
    let showsPrecipitationAmounts: Bool
    let temperatureUnit: String
    let precipitationUnit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)

            Image(systemName: symbolName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Text(temperature)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if showsPrecipitationProbability, let probability = forecast.precipitationProbability {
                Text("\(probability)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            } else if showsPrecipitationAmounts, let precipitation = forecast.precipitation {
                Text("\(precipitation.formatted(.number.precision(.fractionLength(0...1)))) \(precipitationUnit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            } else if showsWind, let windSpeed = forecast.windSpeed {
                Text("\(windSpeed.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        )
    }

    private var label: String {
        guard let date = forecast.date else {
            return "Soon"
        }

        if showsDate {
            return date.formatted(.dateTime.weekday(.abbreviated).day())
        }

        return date.formatted(.dateTime.hour())
    }

    private var symbolName: String {
        switch forecast.condition?.lowercased() {
        case "clear-night":
            return "moon.stars.fill"
        case "partlycloudy", "partly cloudy":
            return "cloud.sun.fill"
        case "cloudy":
            return "cloud.fill"
        case "rainy", "pouring":
            return "cloud.rain.fill"
        case "snowy", "snowy-rainy":
            return "cloud.snow.fill"
        case "sunny":
            return "sun.max.fill"
        default:
            return "cloud.sun.fill"
        }
    }

    private var temperature: String {
        guard let temperature = forecast.temperature else {
            return "—"
        }

        return "\(temperature.formatted(.number.precision(.fractionLength(0...1))))\(temperatureUnit)"
    }
}

private struct LogbookEntryRow: View {
    let entry: HALogbookEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.84))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(entry.when, format: .relative(presentation: .named))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let state = entry.state, !state.isEmpty {
                Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var title: String {
        if let message = entry.message, !message.isEmpty {
            return message
        }

        return entry.name ?? entry.entityID ?? "Activity"
    }
}

private struct WeatherChartSample: Identifiable {
    let id: String
    let date: Date
    let temperature: Double
    let precipitationProbability: Int?
    let precipitationAmount: Double?
}

private struct WeatherRadarSample: Identifiable {
    let id: String
    let date: Date
    let precipitationProbability: Double
    let precipitationAmount: Double
}

private struct WeatherForecastPill: View {
    let forecast: HAWeatherForecastEntry
    let type: HAWeatherForecastType
    let roundTemperature: Bool
    let temperatureUnit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }

            Text(primaryTemperature)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let lowTemperature {
                Text(lowTemperature)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(minWidth: 104, maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.05))
        )
    }

    private var label: String {
        guard let date = forecast.date else { return "Soon" }

        switch type {
        case .hourly:
            return date.formatted(.dateTime.hour())
        case .twiceDaily:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .daily:
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
    }

    private var iconName: String {
        switch forecast.condition?.lowercased() {
        case "clear-night":
            return "moon.stars.fill"
        case "partlycloudy", "partly cloudy":
            return "cloud.sun.fill"
        case "cloudy":
            return "cloud.fill"
        case "rainy", "pouring":
            return "cloud.rain.fill"
        case "snowy", "snowy-rainy":
            return "cloud.snow.fill"
        case "sunny":
            return "sun.max.fill"
        default:
            return "cloud.sun.fill"
        }
    }

    private var primaryTemperature: String {
        format(forecast.temperature)
    }

    private var lowTemperature: String? {
        guard let templow = forecast.templow else { return nil }
        return "Low \(format(templow))"
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatted = roundTemperature
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(formatted)\(temperatureUnit)"
    }
}

private struct NativeWeatherTrendChart: View {
    let samples: [WeatherChartSample]
    let accent: Color

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.date),
                    y: .value("Temperature", sample.temperature)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.28), accent.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("Temperature", sample.temperature)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 124)
    }
}

private struct NativeWeatherRadarChart: View {
    let samples: [WeatherRadarSample]
    let accent: Color
    let precipitationUnit: String

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                BarMark(
                    x: .value("Time", sample.date),
                    y: .value("Probability", sample.precipitationProbability)
                )
                .foregroundStyle(accent.opacity(0.7))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if sample.precipitationAmount > 0 {
                        Text("\(sample.precipitationAmount.formatted(.number.precision(.fractionLength(0...1))))\(precipitationUnit)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 138)
    }
}

private struct GaugeRingView: View {
    let progress: Double
    let tint: Color
    let valueText: String
    let subtitle: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text(valueText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 18)
        }
        .frame(width: 132, height: 132)
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

    private var yDomain: ClosedRange<Double>? {
        let values = displaySamples.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return nil
        }

        if minimum == maximum {
            let padding = max(abs(minimum) * 0.08, 1)
            return (minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.14, 0.5)
        return (minimum - padding)...(maximum + padding)
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
        .chartYScale(domain: yDomain ?? 0...1)
        .frame(height: 120)
    }
}
