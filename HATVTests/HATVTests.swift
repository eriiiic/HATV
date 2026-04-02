import Foundation
import Testing
@testable import HATV

struct HATVTests {
    @Test func decodesLovelaceViewsAndCards() throws {
        let json = """
        {
          "views": [
            {
              "title": "Main",
              "path": "main",
              "sections": [
                {
                  "title": "Lights",
                  "cards": [
                    {
                      "type": "entities",
                      "title": "Downstairs",
                      "entities": [
                        "light.living_room",
                        {
                          "entity": "switch.espresso_machine",
                          "name": "Coffee"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """

        let config = try JSONDecoder().decode(HALovelaceConfig.self, from: Data(json.utf8))

        #expect(config.views.count == 1)
        #expect(config.views.first?.sections.count == 1)
        #expect(config.views.first?.sections.first?.cards.first?.entities.count == 2)
    }

    @Test func parsesTapActionTargets() {
        let action = HAActionConfig(
            raw: [
                "action": .string("perform-action"),
                "perform_action": .string("light.turn_on"),
                "target": .object([
                    "entity_id": .array([.string("light.office"), .string("light.kitchen")])
                ])
            ]
        )

        #expect(action?.serviceName == "light.turn_on")
        #expect(action?.targetEntityIDs == ["light.office", "light.kitchen"])
    }

    @Test func decodesDashboardWithoutExplicitID() throws {
        let json = """
        {
          "mode": "yaml",
          "icon": "mdi:flower",
          "title": "UI Lovelace Minimalist 1",
          "filename": "ui_lovelace_minimalist/dashboard/ui-lovelace.yaml",
          "show_in_sidebar": true,
          "require_admin": false,
          "url_path": "ui-lovelace-minimalist"
        }
        """

        let dashboard = try JSONDecoder().decode(HADashboardSummary.self, from: Data(json.utf8))
        #expect(dashboard.id == "ui-lovelace-minimalist")
        #expect(dashboard.title == "UI Lovelace Minimalist 1")
    }

    @Test func decodesStrategyDashboardWithoutViews() throws {
        let json = """
        {
          "strategy": {
            "type": "original-states"
          }
        }
        """

        let config = try JSONDecoder().decode(HALovelaceConfig.self, from: Data(json.utf8))
        #expect(config.views.isEmpty)
        #expect(config.isStrategyDashboard)
    }

    @Test func formatsStateValues() throws {
        let json = """
        {
          "entity_id": "sensor.outdoor_temperature",
          "state": "21.4",
          "attributes": {
            "friendly_name": "Outdoor temperature",
            "unit_of_measurement": "°C"
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let state = try JSONDecoder().decode(HAEntityState.self, from: Data(json.utf8))
        #expect(state.friendlyName == "Outdoor temperature")
        #expect(state.displayState.contains("21"))
        #expect(state.displayState.contains("°C"))
    }

    @Test func persistsTokenForCurrentRuntime() throws {
        let store = KeychainTokenStore()
        let account = "test-\(UUID().uuidString)"
        let token = "debug-token"

        try store.save(token, account: account)
        #expect(try store.load(account: account) == token)

        try store.delete(account: account)
        #expect(try store.load(account: account) == nil)
    }
}
