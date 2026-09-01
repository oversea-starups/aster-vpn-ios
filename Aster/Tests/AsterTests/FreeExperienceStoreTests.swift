import XCTest
@testable import Aster

@MainActor
final class FreeExperienceStoreTests: XCTestCase {
    func testOneTimeExperienceStartsOnlyAfterFirstReadyConnection() {
        let defaults = UserDefaults(suiteName: "AsterFreeExperienceTests-\(UUID().uuidString)")!
        var clock = Date(timeIntervalSince1970: 10_000)
        let claim = TestFreeExperienceClaim()
        let store = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })

        XCTAssertTrue(store.canStartOrContinue)
        XCTAssertEqual(store.remainingSeconds, 600)
        XCTAssertTrue(store.startWhenReady())
        XCTAssertTrue(claim.hasClaimed)
        XCTAssertTrue(store.isActive)

        clock = clock.addingTimeInterval(601)
        store.refresh()
        XCTAssertFalse(store.isActive)
        XCTAssertEqual(store.remainingSeconds, 0)
        XCTAssertFalse(store.startWhenReady())
    }

    func testClaimSurvivesRestorationAndCannotBeResetByReinstallState() {
        let defaults = UserDefaults(suiteName: "AsterFreeExperienceTests-\(UUID().uuidString)")!
        let clock = Date(timeIntervalSince1970: 20_000)
        let claim = TestFreeExperienceClaim()
        let first = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })
        XCTAssertTrue(first.startWhenReady())

        let restored = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })
        XCTAssertTrue(restored.isActive)
        XCTAssertTrue(restored.hasBeenClaimed)
        XCTAssertFalse(restored.startWhenReady())
    }
}

private final class TestFreeExperienceClaim: FreeExperienceClaiming {
    var hasClaimed = false
    func markClaimed() { hasClaimed = true }
}
