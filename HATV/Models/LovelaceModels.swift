import Foundation

nonisolated struct HADashboardSummary: Codable, Identifiable, Equatable, Sendable {
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

    var isStrategyDashboard: Bool {
        strategy != nil && views.isEmpty
    }

    var allCards: [HAAnyConfig] {
        views.flatMap(\.allCards)
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
        let trimmedCandidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = (path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmedCandidate == trimmedPath || trimmedCandidate == displayTitle.lowercased()
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

            guard let object = item.objectValue, let entityID = object["entity"]?.stringValue else {
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

    var heading: String? {
        raw["heading"]?.stringValue ?? title
    }

    var secondaryText: String? {
        raw["subtitle"]?.stringValue
    }

    var flattened: [HAAnyConfig] {
        [self] + childCards.flatMap(\.flattened)
    }

    var referencedEntityIDs: [String] {
        let directEntities = entities.map(\.entityID)
        let singles = [entityID, cameraEntityID].compactMap { $0 }
        return Array(Set(singles + directEntities + childCards.flatMap(\.referencedEntityIDs)))
    }
}
