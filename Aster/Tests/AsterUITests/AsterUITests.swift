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
        app.buttons["locationPickerButton"].tap()
        XCTAssertTrue(app.staticTexts["Choose a region"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        app.buttons["watchRewardedAdButton"].tap()
        XCTAssertTrue(app.staticTexts["rewardedAccessTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Never shown automatically"].exists)
        app.buttons["Close"].tap()

        app.buttons["showPaywallButton"].tap()
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unlimited VPN time"].exists)
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Terms"].exists)
    }

    func testFirstUseDataDisclosureUsesProductionCopy() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-privacy_disclosure_acknowledged_v1", "NO"]
        app.launch()

        XCTAssertTrue(app.staticTexts["privacyDisclosureTitle"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["VPN connection"].exists)
        XCTAssertTrue(app.staticTexts["On this device"].exists)
        XCTAssertTrue(app.staticTexts["Optional rewarded ads"].exists)
        XCTAssertTrue(app.staticTexts["Subscriptions"].exists)
        XCTAssertTrue(app.buttons["acceptPrivacyDisclosureButton"].exists)
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
    }

    func testHomeAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Not protected"].waitForExistence(timeout: 8))
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
    }

    func testRewardAndPaywallAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Not protected"].waitForExistence(timeout: 8))

        app.buttons["watchRewardedAdButton"].tap()
        XCTAssertTrue(app.staticTexts["rewardedAccessTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["10 minutes per completed ad"].exists)
        XCTAssertTrue(app.staticTexts["5-minute break between ads"].exists)
        XCTAssertTrue(app.staticTexts["Up to 4 rewards in a rolling 24 hours"].exists)
        XCTAssertFalse(app.staticTexts["(ledger.rewardsRemainingInWindow) rewards remain in the current 24-hour window."].exists)
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
        app.buttons["Close"].tap()

        app.buttons["showPaywallButton"].tap()
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 5))
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
    }

    func testLocationsAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["locationPickerButton"].waitForExistence(timeout: 8))
        app.buttons["locationPickerButton"].tap()
        XCTAssertTrue(app.staticTexts["Choose a region"].waitForExistence(timeout: 5))
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast])
        }
    }

    func testTabNavigationAndAccountSurface() {
        let app = launchApp()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tabBars.buttons["Locations"].exists)
        XCTAssertTrue(app.tabBars.buttons["Account"].exists)

        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Free plan"].exists || app.staticTexts["Aster Pro"].exists)
        XCTAssertTrue(app.buttons["accountPrivacyChoicesButton"].exists)
        XCTAssertTrue(app.staticTexts["Terms of use"].exists)
    }

    func testHomeUsesCircularConnectionControlAndPrioritizesPro() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["connectButton"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["connectButton"].label.contains("Connect VPN"))
        XCTAssertTrue(app.otherElements["protectionTimeSummary"].exists)
        XCTAssertTrue(app.staticTexts["Free time"].exists || app.staticTexts["Protection time"].exists)
        XCTAssertTrue(app.buttons["showPaywallButton"].exists)
        XCTAssertTrue(app.buttons["watchRewardedAdButton"].exists)
    }

    func testFirstUseDisclosureRemainsReachableAtLargestAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-privacy_disclosure_acknowledged_v1", "NO",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["privacyDisclosureTitle"].waitForExistence(timeout: 8))
        XCTAssertTrue(scrollToHittable(app.buttons["acceptPrivacyDisclosureButton"], in: app))
    }

    func testConversionActionsRemainReachableAtLargestAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-privacy_disclosure_acknowledged_v1", "YES",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let connect = app.buttons["connectButton"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8))
        XCTAssertTrue(connect.isHittable)

        let reward = app.buttons["watchRewardedAdButton"]
        XCTAssertTrue(scrollToHittable(reward, in: app))
        reward.tap()
        XCTAssertTrue(app.staticTexts["rewardedAccessTitle"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()

        let paywall = app.buttons["showPaywallButton"]
        XCTAssertTrue(scrollToHittable(paywall, in: app))
        paywall.tap()
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 5))
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
        return element.isHittable
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-privacy_disclosure_acknowledged_v1", "YES"]
        app.launch()
        return app
    }
}
