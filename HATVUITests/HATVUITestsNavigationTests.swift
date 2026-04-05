import XCTest

final class HATVUITestsNavigationTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRemoteDownNavigationKeepsDashboardResponsive() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(8)

        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            remote.press(.down)
            sleep(1)
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "After Remote Down"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(app.state, .runningForeground)
    }
}
