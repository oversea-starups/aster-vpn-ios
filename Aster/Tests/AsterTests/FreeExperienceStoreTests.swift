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
        var clock = Date(timeIntervalSince1970: 20_000)
        let claim = TestFreeExperienceClaim()
        let first = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })
        XCTAssertTrue(first.startWhenReady())
        clock = clock.addingTimeInterval(120)
        first.refresh()

        let restored = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })
        XCTAssertFalse(restored.isActive)
        XCTAssertTrue(restored.hasBeenClaimed)
        XCTAssertEqual(restored.remainingSeconds, 480)
        XCTAssertTrue(restored.startWhenReady())
    }

    func testAllowanceCountsOnlyProtectedUsageAndResumesAfterDisconnect() {
        let defaults = UserDefaults(suiteName: "AsterFreeExperienceTests-\(UUID().uuidString)")!
        var clock = Date(timeIntervalSince1970: 30_000)
        let claim = TestFreeExperienceClaim()
        let store = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })

        XCTAssertTrue(store.startWhenReady())
        clock = clock.addingTimeInterval(120)
        store.refresh()
        XCTAssertEqual(store.remainingSeconds, 480)

        store.pauseUsage()
        XCTAssertFalse(store.isActive)
        clock = clock.addingTimeInterval(900)
        store.refresh()
        XCTAssertEqual(store.remainingSeconds, 480)
        XCTAssertTrue(store.canStartOrContinue)

        XCTAssertTrue(store.startWhenReady())
        clock = clock.addingTimeInterval(480)
        store.refresh()
        XCTAssertEqual(store.remainingSeconds, 0)
        XCTAssertFalse(store.isActive)
        XCTAssertFalse(store.canStartOrContinue)
    }

    func testLegacyWallClockRecordMigratesToPausedUsageLedger() {
        let defaults = UserDefaults(suiteName: "AsterFreeExperienceTests-\(UUID().uuidString)")!
        var clock = Date(timeIntervalSince1970: 40_000)
        let claim = TestFreeExperienceClaim()
        claim.markClaimed()
        defaults.set(clock.addingTimeInterval(300).timeIntervalSince1970, forKey: "aster.free_experience.expiration")

        let store = FreeExperienceStore(defaults: defaults, keychain: claim, now: { clock })
        XCTAssertEqual(store.remainingSeconds, 300)
        XCTAssertFalse(store.isActive)

        clock = clock.addingTimeInterval(900)
        store.refresh()
        XCTAssertEqual(store.remainingSeconds, 300)
        XCTAssertTrue(store.startWhenReady())
    }
}

private final class TestFreeExperienceClaim: FreeExperienceClaiming {
    var hasClaimed = false
    func markClaimed() { hasClaimed = true }
}
