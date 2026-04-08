import Foundation

typealias JSONDictionary = [String: JSONValue]

nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object(JSONDictionary)
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(JSONDictionary.self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard let doubleValue else { return nil }
        return Int(doubleValue)
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var truthyBoolValue: Bool? {
        if let boolValue {
            return boolValue
        }

        guard let stringValue else {
            return nil
        }

        switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "on":
            return true
        case "false", "no", "0", "off":
            return false
        default:
            return nil
        }
    }

    var lossyDoubleValue: Double? {
        if let doubleValue {
            return doubleValue
        }

        guard let stringValue else {
            return nil
        }

        return Double(stringValue)
    }

    var lossyIntValue: Int? {
        if let intValue {
            return intValue
        }

        guard let stringValue else {
            return nil
        }

        return Int(stringValue)
    }

    var objectValue: JSONDictionary? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var compactDisplayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return value.formatted(.number.precision(.fractionLength(0...2)))
        case .bool(let value):
            return value ? "Yes" : "No"
        case .array(let values):
            let rendered = values.prefix(3).map(\.compactDisplayString)
            if rendered.isEmpty {
                return "—"
            }
            if values.count > 3 {
                return rendered.joined(separator: ", ") + " +\(values.count - 3)"
            }
            return rendered.joined(separator: ", ")
        case .object(let value):
            return "\(value.count) values"
        case .null:
            return "—"
        }
    }
}
