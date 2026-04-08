import Foundation

nonisolated struct DebugHomeAssistantOverride: Sendable {
    let name: String
    let baseURLString: String
    let accessToken: String
    let autoConnect: Bool
    let moreInfoEntityID: String?
    let moreInfoTitle: String?

    static func load() -> DebugHomeAssistantOverride? {
        #if DEBUG
        let defaults = UserDefaults.standard
        let baseURL = defaults.string(forKey: "debug.home_assistant_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = defaults.string(forKey: "debug.home_assistant_token")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !baseURL.isEmpty, !token.isEmpty else {
            return nil
        }

        let name = defaults.string(forKey: "debug.home_assistant_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let autoConnect = defaults.object(forKey: "debug.home_assistant_auto_connect") as? Bool ?? true
        let moreInfoEntityID = defaults.string(forKey: "debug.home_assistant_more_info_entity")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let moreInfoTitle = defaults.string(forKey: "debug.home_assistant_more_info_title")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return DebugHomeAssistantOverride(
            name: name?.isEmpty == false ? name! : "Home Assistant Debug",
            baseURLString: baseURL,
            accessToken: token,
            autoConnect: autoConnect,
            moreInfoEntityID: moreInfoEntityID?.isEmpty == false ? moreInfoEntityID : nil,
            moreInfoTitle: moreInfoTitle?.isEmpty == false ? moreInfoTitle : nil
        )
        #else
        return nil
        #endif
    }
}
