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

    @Test func restoresPreferredViewUsingSavedPathOrTitle() throws {
        let json = """
        {
          "views": [
            {
              "title": "Overview",
              "path": "overview",
              "cards": []
            },
            {
              "title": "Cameras",
              "path": "cams",
              "cards": []
            }
          ]
        }
        """

        let config = try JSONDecoder().decode(HALovelaceConfig.self, from: Data(json.utf8))

        #expect(config.preferredViewIndex(path: "cams", title: nil) == 1)
        #expect(config.preferredViewIndex(path: nil, title: "overview") == 0)
    }

    @Test func parsesRoomSummaryCardsWithEntityIdentifiers() throws {
        let json = """
        {
          "type": "custom:room-summary-card",
          "area_name": "Rez de Chaussee",
          "navigate": "/essentiels-matemale/RdC",
          "entities": [
            {
              "entity_id": "climate.chauffage_rdc",
              "icon": "mdi:home-thermometer",
              "tap_action": {
                "action": "more-info"
              }
            },
            {
              "entity_id": "light.table_a_manger"
            }
          ],
          "lights": ["light.table_a_manger"],
          "sensors": ["sensor.cuisine_total_power"]
        }
        """

        let card = try JSONDecoder().decode(HAAnyConfig.self, from: Data(json.utf8))

        #expect(card.entities.map(\.entityID) == ["climate.chauffage_rdc", "light.table_a_manger"])
        #expect(card.roomLights == ["light.table_a_manger"])
        #expect(card.roomSensors == ["sensor.cuisine_total_power"])
        #expect(card.primaryAction?.kind == "navigate")
        #expect(card.primaryAction?.navigationPath == "/essentiels-matemale/RdC")
    }

    @Test func extractsTemplateEntityReferencesFromCards() throws {
        let json = """
        {
          "type": "custom:mushroom-chips-card",
          "chips": [
            {
              "type": "template",
              "content": "{{ states('sensor.machine_a_laver_active') }}",
              "icon": "mdi:washing-machine"
            },
            {
              "type": "entity",
              "entity": "sensor.puissance_active_linky"
            }
          ]
        }
        """

        let card = try JSONDecoder().decode(HAAnyConfig.self, from: Data(json.utf8))

        #expect(Set(card.referencedEntityIDs) == [
            "sensor.machine_a_laver_active",
            "sensor.puissance_active_linky"
        ])
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

    @Test func formatsLightAndWeatherStateValues() throws {
        let lightJSON = """
        {
          "entity_id": "light.table_a_manger",
          "state": "on",
          "attributes": {
            "friendly_name": "Table a manger",
            "brightness": 128
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let weatherJSON = """
        {
          "entity_id": "weather.capcir",
          "state": "partly_cloudy",
          "attributes": {
            "friendly_name": "Capcir",
            "temperature": 11.5
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let light = try JSONDecoder().decode(HAEntityState.self, from: Data(lightJSON.utf8))
        let weather = try JSONDecoder().decode(HAEntityState.self, from: Data(weatherJSON.utf8))

        #expect(light.brightnessPercent == 50)
        #expect(light.displayState == "50%")
        #expect(weather.displayState.contains("11"))
        #expect(weather.displayState.contains("°"))
        #expect(weather.subtitle == "Partly Cloudy")
    }

    @Test @MainActor func sortsVideoHubCamerasAlphabetically() throws {
        let drivewayJSON = """
        {
          "entity_id": "camera.driveway",
          "state": "streaming",
          "attributes": {
            "friendly_name": "Driveway"
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let frontDoorJSON = """
        {
          "entity_id": "camera.front_door",
          "state": "idle",
          "attributes": {
            "friendly_name": "Front Door"
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let lightJSON = """
        {
          "entity_id": "light.patio",
          "state": "on",
          "attributes": {
            "friendly_name": "Patio"
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let viewModel = RootViewModel()
        let driveway = try JSONDecoder().decode(HAEntityState.self, from: Data(drivewayJSON.utf8))
        let frontDoor = try JSONDecoder().decode(HAEntityState.self, from: Data(frontDoorJSON.utf8))
        let patioLight = try JSONDecoder().decode(HAEntityState.self, from: Data(lightJSON.utf8))

        viewModel.entityStates = [
            driveway.entityID: driveway,
            frontDoor.entityID: frontDoor,
            patioLight.entityID: patioLight
        ]

        #expect(viewModel.allCameraStates.map(\.friendlyName) == ["Driveway", "Front Door"])
    }

    @Test func preservesQueryStringWhenResolvingRelativeCameraURLs() async throws {
        let client = HomeAssistantClient(baseURL: URL(string: "https://ha.example.com")!, token: "debug")
        let url = await client.absoluteURL(for: "/api/hls/playlist.m3u8?authSig=abc123&part=1")

        #expect(url.absoluteString == "https://ha.example.com/api/hls/playlist.m3u8?authSig=abc123&part=1")
    }

    @Test @MainActor func hidesCameraTilesAndCameraCards() throws {
        let drivewayJSON = """
        {
          "entity_id": "camera.driveway",
          "state": "streaming",
          "attributes": {
            "friendly_name": "Driveway"
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let frontDoorJSON = """
        {
          "entity_id": "camera.front_door",
          "state": "idle",
          "attributes": {
            "friendly_name": "Front Door"
          },
          "last_changed": null,
          "last_updated": null
        }
        """

        let viewModel = RootViewModel()
        let driveway = try JSONDecoder().decode(HAEntityState.self, from: Data(drivewayJSON.utf8))
        let frontDoor = try JSONDecoder().decode(HAEntityState.self, from: Data(frontDoorJSON.utf8))

        viewModel.entityStates = [
            driveway.entityID: driveway,
            frontDoor.entityID: frontDoor
        ]
        viewModel.hiddenCameraEntityIDs = ["camera.front_door"]

        let hiddenCameraCard = try JSONDecoder().decode(HAAnyConfig.self, from: Data("""
        {
          "type": "picture-entity",
          "entity": "camera.front_door"
        }
        """.utf8))

        let visibleCameraCard = try JSONDecoder().decode(HAAnyConfig.self, from: Data("""
        {
          "type": "picture-entity",
          "entity": "camera.driveway"
        }
        """.utf8))

        #expect(viewModel.visibleCameraStates.map(\.entityID) == ["camera.driveway"])
        #expect(viewModel.hiddenCameraStates.map(\.entityID) == ["camera.front_door"])
        #expect(viewModel.shouldDisplayCard(hiddenCameraCard) == false)
        #expect(viewModel.shouldDisplayCard(visibleCameraCard) == true)
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
