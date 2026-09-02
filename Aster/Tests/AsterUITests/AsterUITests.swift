import XCTest

@MainActor
final class AsterUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCoreAccessAndSubscriptionFlowUsesProductionCopy() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Not protected"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["connectButton"].exists)
        XCTAssertTrue(app.buttons["locationPickerButton"].exists)
        app.buttons["showPaywallButton"].tap()
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unlimited VPN time"].exists)
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Terms"].exists)
    }

    func testHomeAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Not protected"].waitForExistence(timeout: 8))
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
    }

    func testLocationsAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["locationPickerButton"].waitForExistence(timeout: 8))
        app.buttons["locationPickerButton"].tap()
        let locationsSegment = app.segmentedControls.buttons["Locations"]
        XCTAssertTrue(locationsSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(locationsSegment.isSelected)
        locationsSegment.tap()
        XCTAssertTrue(
            app.staticTexts["Locations are temporarily unavailable"].exists ||
            app.staticTexts["Updated"].exists ||
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'location_'" )).firstMatch.exists
        )
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
    }

    func testTabNavigationAndAccountSurface() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["VIP"].exists)
        XCTAssertTrue(app.tabBars.buttons["Account"].exists)
        app.tabBars.buttons["VIP"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["VIP"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["VIP"].isSelected)
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Free plan"].exists || app.staticTexts["Aster Pro"].exists)
        XCTAssertFalse(app.buttons["accountPrivacyChoicesButton"].exists)
        XCTAssertTrue(app.staticTexts["Terms of use"].exists)
    }

    func testConversionActionsRemainReachableAtLargestAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch()

        let connect = app.buttons["connectButton"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        XCTAssertTrue(connect.isHittable)
        let paywall = app.buttons["showPaywallButton"]
        XCTAssertTrue(scrollToHittable(paywall, in: app))
        paywall.tap()
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 5))
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        return element.isHittable
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }
}
