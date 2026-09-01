import Combine
import Foundation
import Security

/// A one-time, ten-minute first-connection experience. The claim is kept in
/// Keychain so deleting and reinstalling the app cannot reset the allowance.
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
    private var endDate: Date?

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
        isActive || (!keychain.hasClaimed && remainingSeconds > 0)
    }

    var hasBeenClaimed: Bool { keychain.hasClaimed }

    func startWhenReady() -> Bool {
        refresh()
        guard !keychain.hasClaimed, remainingSeconds > 0 else { return false }
        keychain.markClaimed()
        let expiry = now().addingTimeInterval(Self.duration)
        endDate = expiry
        defaults.set(expiry.timeIntervalSince1970, forKey: Keys.expiration)
        isActive = true
        startTicker()
        return true
    }

    func refresh() {
        guard let endDate else {
            remainingSeconds = keychain.hasClaimed ? 0 : Int(Self.duration)
            isActive = false
            return
        }
        let remaining = max(0, Int(ceil(endDate.timeIntervalSince(now()))))
        remainingSeconds = remaining
        isActive = remaining > 0
        if remaining == 0 {
            ticker?.cancel()
            ticker = nil
        }
    }

    deinit { ticker?.cancel() }

    private func restore() {
        let timestamp = defaults.double(forKey: Keys.expiration)
        if timestamp > 0 { endDate = Date(timeIntervalSince1970: timestamp) }
        refresh()
        if isActive { startTicker() }
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

    private enum Keys { static let expiration = "aster.free_experience.expiration" }
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
