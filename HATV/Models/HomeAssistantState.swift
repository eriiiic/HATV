import Foundation

nonisolated struct HAEntityState: Codable, Identifiable, Equatable, Sendable {
    let entityID: String
    let state: String
    let attributes: JSONDictionary
    let lastChanged: String?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    var id: String { entityID }

    var domain: String {
        entityID.split(separator: ".").first.map(String.init) ?? entityID
    }

    var friendlyName: String {
        if let name = attributes["friendly_name"]?.stringValue, !name.isEmpty {
            return name
        }

        return entityID
            .split(separator: ".")
            .dropFirst()
            .joined(separator: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var iconName: String {
        switch domain {
        case "alarm_control_panel": return "shield.lefthalf.filled"
        case "binary_sensor": return "dot.radiowaves.left.and.right"
        case "button", "input_button": return "hand.tap.fill"
        case "camera": return "video.fill"
        case "climate": return "thermometer.medium"
        case "cover": return "door.left.hand.open"
        case "fan": return "fan.fill"
        case "light": return "lightbulb.fill"
        case "lock": return "lock.fill"
        case "media_player": return "play.tv.fill"
        case "scene": return "sparkles"
        case "script": return "play.square.fill"
        case "sensor": return "gauge.with.dots.needle.50percent"
        case "switch": return "power"
        case "vacuum": return "sparkles.tv.fill"
        case "weather": return "cloud.sun.fill"
        default: return "square.grid.2x2.fill"
        }
    }

    var displayState: String {
        if let unit = attributes["unit_of_measurement"]?.stringValue, let number = numericState {
            return "\(number.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        }

        if domain == "light", let brightnessPercent {
            return state.lowercased() == "on" ? "\(brightnessPercent)%" : "Off"
        }

        if domain == "cover", let position = attributes["current_position"]?.intValue {
            return "\(position)%"
        }

        if domain == "climate" {
            if let current = attributes["current_temperature"]?.doubleValue {
                return "\(current.formatted(.number.precision(.fractionLength(0...1))))°"
            }
            if let target = attributes["temperature"]?.doubleValue {
                return "\(target.formatted(.number.precision(.fractionLength(0...1))))°"
            }
        }

        if domain == "weather", let temperature = attributes["temperature"]?.doubleValue {
            return "\(temperature.formatted(.number.precision(.fractionLength(0...1))))°"
        }

        return state
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var subtitle: String? {
        if domain == "weather" {
            return state.replacingOccurrences(of: "_", with: " ").capitalized
        }

        if domain == "media_player" {
            return mediaSubtitle ?? appName
        }

        if let secondary = attributes["device_class"]?.stringValue {
            return secondary.replacingOccurrences(of: "_", with: " ").capitalized
        }

        if domain == "camera", let mode = attributes["frontend_stream_type"]?.stringValue {
            return mode.uppercased()
        }

        return nil
    }

    var numericState: Double? {
        Double(state)
    }

    var currentTemperature: Double? {
        attributes["current_temperature"]?.doubleValue
    }

    var targetTemperature: Double? {
        attributes["temperature"]?.doubleValue
    }

    var brightnessPercent: Int? {
        guard let brightness = attributes["brightness"]?.doubleValue else {
            return nil
        }

        return min(max(Int((brightness / 255.0) * 100.0), 0), 100)
    }

    var humidity: Int? {
        attributes["humidity"]?.intValue
    }

    var mediaTitle: String? {
        attributes["media_title"]?.stringValue
    }

    var mediaSubtitle: String? {
        attributes["media_artist"]?.stringValue
            ?? attributes["source"]?.stringValue
    }

    var appName: String? {
        attributes["app_name"]?.stringValue
    }

    var volumePercent: Int? {
        guard let level = attributes["volume_level"]?.doubleValue else {
            return nil
        }

        return min(max(Int(level * 100.0), 0), 100)
    }

    var isActive: Bool {
        switch state.lowercased() {
        case "on", "open", "playing", "home", "armed_away", "armed_home", "heat", "cool":
            return true
        default:
            return false
        }
    }

    var isToggleLike: Bool {
        [
            "automation",
            "fan",
            "humidifier",
            "input_boolean",
            "light",
            "media_player",
            "remote",
            "switch",
            "vacuum",
            "water_heater"
        ].contains(domain)
    }
}
