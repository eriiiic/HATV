import Foundation

enum HATVTopShelfShared {
    static let appGroupIdentifier = "group.app.delattre.me.HATV"
    static let snapshotDefaultsKey = "hatv.top-shelf.snapshot"
    static let urlScheme = "hatv"
    static let videoHubSelectionPath = "__hatv_video_hub__"
}

struct HATVTopShelfCameraSnapshot: Codable, Equatable, Sendable, Identifiable {
    let entityID: String
    let title: String
    let subtitle: String

    var id: String { entityID }
}

struct HATVTopShelfSnapshot: Codable, Equatable, Sendable {
    let locationName: String?
    let dashboardTitle: String?
    let viewTitle: String?
    let viewPath: String?
    let isShowingVideoHub: Bool
    let visibleCameraCount: Int
    let favoriteCameraCount: Int
    let lightsOnCount: Int
    let activeClimateCount: Int
    let activeMediaCount: Int
    let cameraShortcuts: [HATVTopShelfCameraSnapshot]
    let updatedAt: Date
}

enum HATVTopShelfSnapshotStore {
    private static let decoder = JSONDecoder()

    static func read() -> HATVTopShelfSnapshot? {
        guard let defaults = UserDefaults(suiteName: HATVTopShelfShared.appGroupIdentifier),
              let data = defaults.data(forKey: HATVTopShelfShared.snapshotDefaultsKey) else {
            return nil
        }

        return try? decoder.decode(HATVTopShelfSnapshot.self, from: data)
    }
}

enum HATVTopShelfActionURLBuilder {
    static func home() -> URL {
        URL(string: "\(HATVTopShelfShared.urlScheme)://home")!
    }

    static func videoWall() -> URL {
        URL(string: "\(HATVTopShelfShared.urlScheme)://video")!
    }

    static func dashboard(viewPath: String?) -> URL {
        guard let viewPath, !viewPath.isEmpty, viewPath != HATVTopShelfShared.videoHubSelectionPath else {
            return home()
        }

        var components = URLComponents()
        components.scheme = HATVTopShelfShared.urlScheme
        components.host = "dashboard"
        components.queryItems = [
            URLQueryItem(name: "view_path", value: viewPath)
        ]
        return components.url ?? home()
    }

    static func camera(entityID: String) -> URL {
        var components = URLComponents()
        components.scheme = HATVTopShelfShared.urlScheme
        components.host = "camera"
        components.queryItems = [
            URLQueryItem(name: "entity_id", value: entityID)
        ]
        return components.url ?? videoWall()
    }
}

