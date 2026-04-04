import Foundation

enum HAWeatherForecastType: String, Sendable {
    case daily
    case hourly
    case twiceDaily = "twice_daily"
}

nonisolated struct HAWeatherForecastEntry: Decodable, Identifiable, Equatable, Sendable {
    let datetime: String?
    let condition: String?
    let temperature: Double?
    let templow: Double?
    let humidity: Int?
    let precipitation: Double?
    let precipitationProbability: Int?
    let windSpeed: Double?
    let isDaytime: Bool?

    enum CodingKeys: String, CodingKey {
        case datetime
        case condition
        case temperature
        case templow
        case humidity
        case precipitation
        case precipitationProbability = "precipitation_probability"
        case windSpeed = "wind_speed"
        case isDaytime = "is_daytime"
    }

    var id: String {
        datetime ?? "\(condition ?? "forecast")-\(temperature ?? 0)-\(templow ?? 0)"
    }

    var date: Date? {
        guard let datetime else { return nil }
        return Self.dateFormatter.date(from: datetime) ?? Self.fallbackDateFormatter.date(from: datetime)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

nonisolated struct HAWeatherForecastResponse: Decodable, Sendable {
    let serviceResponse: [String: HAWeatherForecastContainer]

    enum CodingKeys: String, CodingKey {
        case serviceResponse = "service_response"
    }
}

nonisolated struct HAWeatherForecastContainer: Decodable, Sendable {
    let forecast: [HAWeatherForecastEntry]
}
