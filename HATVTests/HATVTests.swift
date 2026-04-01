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
}
