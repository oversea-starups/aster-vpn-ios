import Combine
import Foundation
import Security

/// A one-time, ten-minute allowance measured only while the VPN is in use.
/// The claim is kept in Keychain so deleting and reinstalling the app cannot
/// reset the allowance.
@MainActor
final class FreeExperienceStore: ObservableObject {
    static let shared = FreeExperienceStore()
    static let duration: TimeInterval = 10 * 60

    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isActive = false

    private let defaults: UserDefaults
    private let keychain: FreeExperienceClaiming
    private let now: () -> Date
    private var ticker: Task<Void, Never>?
    private var consumedSeconds: TimeInterval = 0
    private var activeSince: Date?

    init(
        defaults: UserDefaults = .standard,
        keychain: FreeExperienceClaiming = KeychainFreeExperienceClaim(),
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.now = now
        restore()
    }

    var canStartOrContinue: Bool {
        remainingSeconds > 0
    }

    var hasBeenClaimed: Bool { keychain.hasClaimed }

    func startWhenReady() -> Bool {
        refresh()
        guard remainingSeconds > 0 else { return false }
        if !keychain.hasClaimed {
            keychain.markClaimed()
        }
        guard activeSince == nil else { return true }
        activeSince = now()
        persist()
        isActive = true
        startTicker()
        return true
    }

    /// Pauses the allowance when the protected connection ends. Time spent
    /// disconnected is never deducted from the user's free allowance.
    func pauseUsage() {
        guard activeSince != nil else {
            isActive = false
            ticker?.cancel()
            ticker = nil
            return
        }

        consumedSeconds = currentConsumedSeconds()
        activeSince = nil
        persist()
        refresh()
    }

    func refresh() {
        guard activeSince != nil else {
            remainingSeconds = max(0, Int(ceil(Self.duration - consumedSeconds)))
            isActive = false
            return
        }

        let consumed = currentConsumedSeconds()
        let remaining = max(0, Int(ceil(Self.duration - consumed)))
        remainingSeconds = remaining
        isActive = remaining > 0
        if remaining == 0 {
            consumedSeconds = Self.duration
            activeSince = nil
            persist()
            ticker?.cancel()
            ticker = nil
        } else {
            // Checkpoint the ledger periodically so a terminated app cannot
            // charge wall-clock time for a session that may have disconnected
            // while the app was not running. At most one ticker interval is
            // left uncheckpointed.
            consumedSeconds = consumed
            activeSince = now()
            persist()
        }
    }

    deinit { ticker?.cancel() }

    private func restore() {
        if let value = defaults.object(forKey: Keys.consumed) as? NSNumber {
            consumedSeconds = min(Self.duration, max(0, value.doubleValue))
        } else if let legacyExpiration = defaults.object(forKey: Keys.legacyExpiration) as? NSNumber,
                  legacyExpiration.doubleValue > 0 {
            // Migrate the previous wall-clock implementation conservatively:
            // preserve the amount that had already elapsed, then pause it.
            let legacyRemaining = max(
                0,
                min(Self.duration, Date(timeIntervalSince1970: legacyExpiration.doubleValue).timeIntervalSince(now()))
            )
            consumedSeconds = Self.duration - legacyRemaining
            defaults.set(consumedSeconds, forKey: Keys.consumed)
            defaults.removeObject(forKey: Keys.legacyExpiration)
        } else if keychain.hasClaimed {
            // A claimed allowance without a local ledger is treated as spent;
            // this preserves the anti-reset guarantee across reinstall or
            // storage corruption.
            consumedSeconds = Self.duration
        }

        if let timestamp = defaults.object(forKey: Keys.activeSince) as? NSNumber,
           timestamp.doubleValue > 0 {
            // The previous process may have been terminated while the tunnel
            // disconnected. Resume accounting only after the live connection
            // reports Protected again; keep the last persisted usage and
            // discard the stale wall-clock anchor.
            activeSince = nil
            defaults.removeObject(forKey: Keys.activeSince)
        }
        refresh()
        if isActive { startTicker() }
    }

    private func currentConsumedSeconds() -> TimeInterval {
        let activeElapsed = activeSince.map { max(0, now().timeIntervalSince($0)) } ?? 0
        return min(Self.duration, consumedSeconds + activeElapsed)
    }

    private func persist() {
        defaults.set(consumedSeconds, forKey: Keys.consumed)
        if let activeSince {
            defaults.set(activeSince.timeIntervalSince1970, forKey: Keys.activeSince)
        } else {
            defaults.removeObject(forKey: Keys.activeSince)
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if !self.isActive { return }
            }
        }
    }

    private enum Keys {
        static let consumed = "aster.free_experience.consumed_seconds"
        static let activeSince = "aster.free_experience.active_since"
        static let legacyExpiration = "aster.free_experience.expiration"
    }
}

protocol FreeExperienceClaiming: AnyObject {
    var hasClaimed: Bool { get }
    func markClaimed()
}

private final class KeychainFreeExperienceClaim: FreeExperienceClaiming {
    private let service = "com.astervpn.Aster.free-experience"
    private let account = "claimed"

    var hasClaimed: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    func markClaimed() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data([1])
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return }
        let update: [String: Any] = [kSecValueData as String: Data([1])]
        SecItemUpdate(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ] as CFDictionary,
            update as CFDictionary
        )
    }
}
