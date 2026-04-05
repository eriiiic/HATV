import Foundation

nonisolated struct HAAreaRegistryEntry: Decodable, Identifiable, Sendable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

nonisolated struct HAEntityRegistryEntry: Decodable, Identifiable, Sendable {
    let id: String
    let entityID: String
    let areaID: String?
    let originalName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entityID = "entity_id"
        case areaID = "area_id"
        case originalName = "original_name"
        case name
    }
}

nonisolated struct HALogbookEntry: Decodable, Identifiable, Equatable, Sendable {
    let entityID: String?
    let name: String?
    let state: String?
    let message: String?
    let when: Date

    enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case name
        case state
        case message
        case when
    }

    var id: String {
        "\(entityID ?? "event")|\(when.timeIntervalSince1970)|\(state ?? message ?? "")"
    }
}
