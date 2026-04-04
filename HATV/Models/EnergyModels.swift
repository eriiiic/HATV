import Foundation

nonisolated enum HAStatisticsPeriod: String, Sendable {
    case fiveMinute = "5minute"
    case hour
    case day
    case month
}

nonisolated struct HAEnergyPreferences: Decodable, Sendable {
    let energySources: [HAEnergySource]
    let deviceConsumption: [HAEnergyDeviceConsumption]

    enum CodingKeys: String, CodingKey {
        case energySources = "energy_sources"
        case deviceConsumption = "device_consumption"
    }

    var primaryPowerStatisticID: String? {
        energySources.lazy
            .compactMap { source in
                source.powerConfig?.statRate ?? source.statRate
            }
            .first
    }
}

nonisolated struct HAEnergySource: Decodable, Sendable {
    let type: String
    let statRate: String?
    let powerConfig: HAEnergyPowerConfig?

    enum CodingKeys: String, CodingKey {
        case type
        case statRate = "stat_rate"
        case powerConfig = "power_config"
    }
}

nonisolated struct HAEnergyPowerConfig: Decodable, Sendable {
    let statRate: String?

    enum CodingKeys: String, CodingKey {
        case statRate = "stat_rate"
    }
}

nonisolated struct HAEnergyDeviceConsumption: Decodable, Sendable {
    let statConsumption: String?
    let statRate: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case statConsumption = "stat_consumption"
        case statRate = "stat_rate"
        case name
    }
}

nonisolated struct HAStatisticBucket: Decodable, Sendable {
    let start: Date
    let end: Date?
    let min: Double?
    let mean: Double?
    let max: Double?
    let sum: Double?

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case min
        case mean
        case max
        case sum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try Self.decodeDate(from: container, key: .start)
        end = try Self.decodeOptionalDate(from: container, key: .end)
        min = try container.decodeIfPresent(Double.self, forKey: .min)
        mean = try container.decodeIfPresent(Double.self, forKey: .mean)
        max = try container.decodeIfPresent(Double.self, forKey: .max)
        sum = try container.decodeIfPresent(Double.self, forKey: .sum)
    }

    var representativeValue: Double? {
        mean ?? sum ?? max ?? min
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date {
        if let milliseconds = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: milliseconds / 1000.0)
        }

        if let isoString = try? container.decode(String.self, forKey: key),
           let parsed = ISO8601DateFormatter().date(from: isoString) {
            return parsed
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unsupported statistics date value."
        )
    }

    private static func decodeOptionalDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Date? {
        guard container.contains(key) else { return nil }
        return try? decodeDate(from: container, key: key)
    }
}
