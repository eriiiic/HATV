//
//  HATVUITestsLaunchTests.swift
//  HATVUITests
//
//  Created by Eric on 01/04/2026.
//

import XCTest

final class HATVUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(8)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settled Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
