import Foundation
import SwiftData

@Model
final class StoredConnection {
    static let defaultID = "default-connection"

    @Attribute(.unique) var id: String
    var name: String
    var baseURLString: String
    var selectedDashboardID: String?
    var selectedDashboardURLPath: String?
    var selectedDashboardTitle: String?
    var selectedViewPath: String?
    var selectedViewTitle: String?
    var autoLaunchDashboard: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = StoredConnection.defaultID,
        name: String = "Home Assistant",
        baseURLString: String = "",
        selectedDashboardID: String? = nil,
        selectedDashboardURLPath: String? = nil,
        selectedDashboardTitle: String? = nil,
        selectedViewPath: String? = nil,
        selectedViewTitle: String? = nil,
        autoLaunchDashboard: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.selectedDashboardID = selectedDashboardID
        self.selectedDashboardURLPath = selectedDashboardURLPath
        self.selectedDashboardTitle = selectedDashboardTitle
        self.selectedViewPath = selectedViewPath
        self.selectedViewTitle = selectedViewTitle
        self.autoLaunchDashboard = autoLaunchDashboard
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
