import Foundation

nonisolated private let templateEntityRegex = try? NSRegularExpression(
    pattern: #"\{\{\s*states\(['"]([^'"]+)['"]\)\s*\}\}"#,
    options: []
)

private extension JSONDictionary {
    nonisolated func string(at path: [String]) -> String? {
        guard let value = value(at: path) else {
            return nil
        }
        return value.stringValue
    }

    nonisolated func object(at path: [String]) -> JSONDictionary? {
        guard let value = value(at: path) else {
            return nil
        }
        return value.objectValue
    }

    nonisolated func value(at path: [String]) -> JSONValue? {
        guard let key = path.first else {
            return nil
        }

        let currentValue = self[key]
        guard path.count > 1 else {
            return currentValue
        }

        return currentValue?.objectValue?.value(at: Array(path.dropFirst()))
    }
}

nonisolated private func templateEntityIDs(in text: String?) -> [String] {
    guard let text, let regex = templateEntityRegex else {
        return []
    }

    let nsText = text as NSString
    return regex
        .matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        .compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
}

nonisolated struct HADashboardSummary: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let urlPath: String
    let requireAdmin: Bool
    let showInSidebar: Bool
    let icon: String?
    let title: String
    let mode: String
    let filename: String?

    enum CodingKeys: String, CodingKey {
        case id
        case urlPath = "url_path"
        case requireAdmin = "require_admin"
        case showInSidebar = "show_in_sidebar"
        case icon
        case title
        case mode
        case filename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath) ?? ""
        let title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Dashboard"
        let filename = try container.decodeIfPresent(String.self, forKey: .filename)

        self.urlPath = urlPath
        self.requireAdmin = try container.decodeIfPresent(Bool.self, forKey: .requireAdmin) ?? false
        self.showInSidebar = try container.decodeIfPresent(Bool.self, forKey: .showInSidebar) ?? true
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon)
        self.title = title
        self.mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "storage"
        self.filename = filename
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? (urlPath.isEmpty ? nil : urlPath)
            ?? filename
            ?? title
    }

    var normalizedURLPath: String? {
        urlPath.isEmpty ? nil : urlPath
    }
}

nonisolated struct HALovelaceConfig: Decodable, Sendable {
    let background: String?
    let views: [HALovelaceView]
    let strategy: JSONValue?

    enum CodingKeys: String, CodingKey {
        case background
        case views
        case strategy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decodeIfPresent(String.self, forKey: .background)
        views = try container.decodeIfPresent([HALovelaceView].self, forKey: .views) ?? []
        strategy = try container.decodeIfPresent(JSONValue.self, forKey: .strategy)
    }

    var isStrategyDashboard: Bool {
        strategy != nil && views.isEmpty
    }

    var allCards: [HAAnyConfig] {
        views.flatMap(\.allCards)
    }

    func preferredViewIndex(path: String?, title: String?) -> Int? {
        views.firstIndex { $0.matchesStoredSelection(path: path, title: title) }
    }
}

nonisolated struct HALovelaceView: Decodable, Identifiable, Sendable {
    let id: String
    let title: String?
    let path: String?
    let icon: String?
    let type: String?
    let cards: [HAAnyConfig]
    let sections: [HASectionConfig]

    enum CodingKeys: String, CodingKey {
        case title
        case path
        case icon
        case type
        case cards
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        cards = try container.decodeIfPresent([HAAnyConfig].self, forKey: .cards) ?? []
        sections = try container.decodeIfPresent([HASectionConfig].self, forKey: .sections) ?? []
        id = path ?? title ?? UUID().uuidString
    }

    var displayTitle: String {
        title?.isEmpty == false ? title! : "Overview"
    }

    var contentCards: [HAAnyConfig] {
        sections.isEmpty ? cards : sections.flatMap(\.cards)
    }

    var allCards: [HAAnyConfig] {
        contentCards.flatMap(\.flattened)
    }

    func matchesNavigationPath(_ candidate: String) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let trimmedPath = (path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return trimmedCandidate == trimmedPath || trimmedCandidate == displayTitle.lowercased()
    }

    func matchesStoredSelection(path: String?, title: String?) -> Bool {
        let storedPath = path?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let currentPath = self.path?.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        if let storedPath, !storedPath.isEmpty, storedPath == currentPath {
            return true
        }

        guard let title, !title.isEmpty else {
            return false
        }

        return displayTitle.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

nonisolated struct HASectionConfig: Decodable, Identifiable, Sendable {
    let id: String
    let title: String?
    let type: String?
    let columnSpan: Int?
    let cards: [HAAnyConfig]

    enum CodingKeys: String, CodingKey {
        case title
        case type
        case columnSpan = "column_span"
        case cards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        columnSpan = try container.decodeIfPresent(Int.self, forKey: .columnSpan)
        cards = try container.decodeIfPresent([HAAnyConfig].self, forKey: .cards) ?? []
        id = title ?? UUID().uuidString
    }
}

nonisolated struct HAEntityItem: Sendable {
    let entityID: String
    let name: String?
    let icon: String?
    let action: HAActionConfig?
}

nonisolated struct HAChipItem: Identifiable, Sendable {
    let id: String
    let type: String
    let entityID: String?
    let content: String?
    let icon: String?
    let showConditions: Bool
    let showTemperature: Bool
    let action: HAActionConfig?
}

nonisolated struct HAActionConfig: Sendable {
    let kind: String
    let navigationPath: String?
    let serviceName: String?
    let targetEntityIDs: [String]
    let serviceData: JSONDictionary

    init?(raw: JSONDictionary) {
        guard let kind = raw["action"]?.stringValue else {
            return nil
        }

        self.kind = kind
        navigationPath = raw["navigation_path"]?.stringValue ?? raw["path"]?.stringValue
        serviceName = raw["perform_action"]?.stringValue ?? raw["service"]?.stringValue
        serviceData = raw["data"]?.objectValue ?? raw["service_data"]?.objectValue ?? [:]

        let target = raw["target"]?.objectValue
        if let ids = target?["entity_id"]?.arrayValue?.compactMap(\.stringValue) {
            targetEntityIDs = ids
        } else if let entityID = target?["entity_id"]?.stringValue {
            targetEntityIDs = [entityID]
        } else if let entityID = serviceData["entity_id"]?.stringValue {
            targetEntityIDs = [entityID]
        } else if let ids = serviceData["entity_id"]?.arrayValue?.compactMap(\.stringValue) {
            targetEntityIDs = ids
        } else {
            targetEntityIDs = []
        }
    }
}

nonisolated struct HAAnyConfig: Decodable, Identifiable, Sendable {
    let id: String
    let raw: JSONDictionary

    init(raw: JSONDictionary) {
        self.raw = raw
        id = raw["view_layout"]?.stringValue
            ?? raw["path"]?.stringValue
            ?? raw["title"]?.stringValue
            ?? raw["entity"]?.stringValue
            ?? UUID().uuidString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(raw: try container.decode(JSONDictionary.self))
    }

    var type: String {
        raw["type"]?.stringValue ?? "unknown"
    }

    var title: String? {
        raw["title"]?.stringValue
    }

    var name: String? {
        raw["name"]?.stringValue
    }

    var label: String? {
        raw["label"]?.stringValue
    }

    var primaryText: String? {
        raw["primary"]?.stringValue ?? name ?? heading
    }

    var entityID: String? {
        raw["entity"]?.stringValue
    }

    var cameraEntityID: String? {
        if let cameraImage = raw["camera_image"]?.stringValue {
            return cameraImage
        }
        return entityID
    }

    var columns: Int {
        raw["columns"]?.intValue ?? 2
    }

    var childCards: [HAAnyConfig] {
        raw["cards"]?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else { return nil }
            return HAAnyConfig(raw: object)
        } ?? []
    }

    var entities: [HAEntityItem] {
        raw["entities"]?.arrayValue?.compactMap { item in
            if let entityID = item.stringValue {
                return HAEntityItem(entityID: entityID, name: nil, icon: nil, action: nil)
            }

            guard let object = item.objectValue,
                  let entityID = object["entity"]?.stringValue ?? object["entity_id"]?.stringValue else {
                return nil
            }

            return HAEntityItem(
                entityID: entityID,
                name: object["name"]?.stringValue,
                icon: object["icon"]?.stringValue,
                action: HAActionConfig(raw: object["tap_action"]?.objectValue ?? [:])
            )
        } ?? []
    }

    var tapAction: HAActionConfig? {
        HAActionConfig(raw: raw["tap_action"]?.objectValue ?? [:])
    }

    var primaryAction: HAActionConfig? {
        if let tapAction {
            return tapAction
        }

        if let navigationPath = raw["navigate"]?.stringValue {
            return HAActionConfig(
                raw: [
                    "action": .string("navigate"),
                    "navigation_path": .string(navigationPath)
                ]
            )
        }

        return nil
    }

    var heading: String? {
        raw["heading"]?.stringValue ?? title
    }

    var secondaryText: String? {
        raw["secondary"]?.stringValue ?? raw["subtitle"]?.stringValue ?? label
    }

    var icon: String? {
        raw["icon"]?.stringValue
    }

    var navigationPath: String? {
        primaryAction?.navigationPath
    }

    var isVerticalLayout: Bool {
        raw["vertical"]?.boolValue ?? false
    }

    var roomAreaName: String? {
        raw["area_name"]?.stringValue
    }

    var roomSensors: [String] {
        raw["sensors"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    var roomLights: [String] {
        raw["lights"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    var roomBackgroundThumbnailPath: String? {
        raw.string(at: ["background", "image", "metadata", "thumbnail"])
    }

    var thermostatEcoTemperature: Double? {
        raw["eco_temperature"]?.doubleValue
    }

    var showsBrightnessControl: Bool {
        raw["show_brightness_control"]?.boolValue ?? false
    }

    var showsColorTemperatureControl: Bool {
        raw["show_color_temp_control"]?.boolValue ?? false
    }

    var miniGraphHoursToShow: Int {
        max(raw["hours_to_show"]?.intValue ?? 24, 1)
    }

    var chips: [HAChipItem] {
        raw["chips"]?.arrayValue?.compactMap { value in
            guard let chip = value.objectValue else {
                return nil
            }

            let entityID = chip["entity"]?.stringValue
            let content = chip["content"]?.stringValue

            return HAChipItem(
                id: entityID ?? content ?? UUID().uuidString,
                type: chip["type"]?.stringValue ?? "template",
                entityID: entityID,
                content: content,
                icon: chip["icon"]?.stringValue,
                showConditions: chip["show_conditions"]?.boolValue ?? false,
                showTemperature: chip["show_temperature"]?.boolValue ?? false,
                action: HAActionConfig(raw: chip["tap_action"]?.objectValue ?? [:])
            )
        } ?? []
    }

    var flattened: [HAAnyConfig] {
        [self] + childCards.flatMap(\.flattened)
    }

    var referencedEntityIDs: [String] {
        let directEntities = entities.map(\.entityID)
        let singles = [entityID, cameraEntityID].compactMap { $0 }
        let templated = templateEntityIDs(in: raw["content"]?.stringValue)
            + templateEntityIDs(in: raw["primary"]?.stringValue)
            + templateEntityIDs(in: raw["secondary"]?.stringValue)
            + templateEntityIDs(in: raw["label"]?.stringValue)
            + chips.flatMap { chip in
                [chip.entityID].compactMap { $0 } + templateEntityIDs(in: chip.content)
            }

        return Array(Set(singles + directEntities + templated + roomSensors + roomLights + childCards.flatMap(\.referencedEntityIDs)))
    }
}
