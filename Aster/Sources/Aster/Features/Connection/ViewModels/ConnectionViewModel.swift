import Combine
import Foundation
import NetworkExtension

enum ConnectionPresentationState: Equatable {
    case unavailable
    case disconnected
    case connecting
    case verifying
    case protected
    case disconnecting
    case reconnecting

    var title: String {
        switch self {
        case .unavailable: return "VPN unavailable"
        case .disconnected: return "Not protected"
        case .connecting: return "Connecting"
        case .verifying: return "Checking protection"
        case .protected: return "Protected"
        case .disconnecting: return "Disconnecting"
        case .reconnecting: return "Reconnecting"
        }
    }

    var detail: String {
        switch self {
        case .unavailable: return "Check the message below to continue."
        case .disconnected: return "Tap to connect."
        case .connecting: return "Connecting securely…"
        case .verifying: return "Checking connection…"
        case .protected: return "VPN is active."
        case .disconnecting: return "Disconnecting…"
        case .reconnecting: return "Reconnecting…"
        }
    }

    var symbolName: String {
        switch self {
        case .protected: return "checkmark.shield.fill"
        case .connecting, .verifying, .disconnecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .unavailable: return "exclamationmark.shield.fill"
        case .disconnected: return "power"
        }
    }

    var actionTitle: String {
        switch self {
        case .protected, .connecting, .verifying, .disconnecting, .reconnecting: return "Disconnect"
        case .unavailable, .disconnected: return "Connect"
        }
    }

    var isProtected: Bool { self == .protected }
    var isTransitioning: Bool {
        self == .connecting || self == .verifying || self == .disconnecting || self == .reconnecting
    }
}

@MainActor
final class ConnectionViewModel: ObservableObject {
    @Published private(set) var presentationState: ConnectionPresentationState = .unavailable
    @Published private(set) var isPro = false
    @Published private(set) var isEntitlementReady = false
    @Published private(set) var selectedLocationName = "Choose a region"
    @Published private(set) var hasSelectedLocation = false
    @Published private(set) var freeExperienceRemainingSeconds = 0
    @Published private(set) var userMessage: String?
    @Published var showsPaywall = false
    @Published var showsLocations = false

    private let vpnManager: VPNManager
    private let subscriptionStore: SubscriptionStore
    private let nodeCatalog: NodeCatalogStore
    private let freeExperience: FreeExperienceStore
    private var vpnStatus: NEVPNStatus = .invalid
    private var isDataPlaneReady = false
    private var actionMessage: String?
    private var vpnMessage: String?
    private var locationMessage: String?
    private var pendingFreeExperience = false
    private var cancellables = Set<AnyCancellable>()

    convenience init() {
        self.init(
            vpnManager: VPNManager.shared,
            subscriptionStore: SubscriptionStore.shared,
            nodeCatalog: NodeCatalogStore.shared,
            freeExperience: FreeExperienceStore.shared
        )
    }

    init(
        vpnManager: VPNManager,
        subscriptionStore: SubscriptionStore,
        nodeCatalog: NodeCatalogStore,
        freeExperience: FreeExperienceStore
    ) {
        self.vpnManager = vpnManager
        self.subscriptionStore = subscriptionStore
        self.nodeCatalog = nodeCatalog
        self.freeExperience = freeExperience
        freeExperienceRemainingSeconds = freeExperience.remainingSeconds

        vpnManager.$status
            .sink { [weak self] status in
                self?.vpnStatus = status
                self?.updatePresentationState()
            }
            .store(in: &cancellables)

        vpnManager.$isDataPlaneReady
            .sink { [weak self] isReady in
                self?.isDataPlaneReady = isReady
                self?.updatePresentationState()
            }
            .store(in: &cancellables)

        vpnManager.$userMessage
            .sink { [weak self] message in
                self?.vpnMessage = message
                self?.updateUserMessage()
            }
            .store(in: &cancellables)

        subscriptionStore.$isPro
            .sink { [weak self] isPro in
                guard let self else { return }
                self.isPro = isPro
            }
            .store(in: &cancellables)

        subscriptionStore.$isEntitlementReady
            .sink { [weak self] isReady in
                guard let self else { return }
                self.isEntitlementReady = isReady
            }
            .store(in: &cancellables)

        nodeCatalog.$selectedNodeID
            .combineLatest(nodeCatalog.$nodes)
            .sink { [weak self] selectedNodeID, nodes in
                guard let self else { return }
                let selected = nodes.first(where: { $0.id == selectedNodeID })
                self.selectedLocationName = selected?.regionName ?? "Choose a region"
                self.hasSelectedLocation = selected != nil
            }
            .store(in: &cancellables)

        nodeCatalog.$userMessage
            .sink { [weak self] message in
                self?.locationMessage = message
                self?.updateUserMessage()
            }
            .store(in: &cancellables)

        freeExperience.$remainingSeconds
            .sink { [weak self] remaining in
                guard let self else { return }
                self.freeExperienceRemainingSeconds = remaining
                if remaining == 0, self.freeExperience.hasBeenClaimed, !self.isPro,
                   self.presentationState == .protected {
                    AsterAnalytics.log(AsterAnalytics.Event.demoEnd, parameters: ["reason": "timeout"])
                    self.vpnManager.disconnect()
                    self.showsPaywall = true
                }
            }
            .store(in: &cancellables)
    }

    func toggleConnection() {
        actionMessage = nil
        updateUserMessage()
        AsterAnalytics.log(
            AsterAnalytics.Event.connectTap,
            parameters: ["source": "home", "location": selectedLocationName, "is_pro": isPro]
        )
        switch presentationState {
        case .protected, .connecting, .verifying, .disconnecting, .reconnecting:
            vpnManager.disconnect()
        case .unavailable, .disconnected:
            guard isEntitlementReady else {
                actionMessage = "Checking your access. Please try again in a moment."
                updateUserMessage()
                return
            }
            guard hasSelectedLocation else {
                showsLocations = true
                return
            }
            guard isPro || freeExperience.canStartOrContinue else {
                showsPaywall = true
                return
            }
            guard nodeCatalog.ensureSelectedConfiguration() else {
                updateUserMessage()
                return
            }
            if !isPro { pendingFreeExperience = true }
            vpnManager.connect()
        }
    }

    func retryVPNSetup() {
        vpnManager.reload()
    }

    func dismissMessage() {
        actionMessage = nil
        vpnMessage = nil
        locationMessage = nil
        vpnManager.clearMessage()
        nodeCatalog.clearMessage()
        updateUserMessage()
    }

    func refreshLocationsIfNeeded() async {
        await nodeCatalog.refreshIfNeeded()
    }

    var canSwitchLocation: Bool {
        presentationState == .disconnected || presentationState == .unavailable
    }

    var canUseFreeExperience: Bool {
        !isPro && freeExperience.canStartOrContinue
    }

    var freeExperienceHasBeenClaimed: Bool {
        freeExperience.hasBeenClaimed
    }

    var formattedFreeExperienceRemaining: String {
        let minutes = freeExperienceRemainingSeconds / 60
        let seconds = freeExperienceRemainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func updatePresentationState() {
        switch vpnStatus {
        case .invalid: presentationState = .unavailable
        case .disconnected: presentationState = .disconnected
        case .connecting: presentationState = .connecting
        case .connected: presentationState = isDataPlaneReady ? .protected : .verifying
        case .disconnecting: presentationState = .disconnecting
        case .reasserting: presentationState = .reconnecting
        @unknown default: presentationState = .unavailable
        }

        if presentationState == .protected, pendingFreeExperience, !isPro {
            pendingFreeExperience = false
            _ = freeExperience.startWhenReady()
            AsterAnalytics.log(AsterAnalytics.Event.demoStart, parameters: ["location": selectedLocationName])
        } else if presentationState == .protected {
            AsterAnalytics.log(
                AsterAnalytics.Event.connectSuccess,
                parameters: ["location": selectedLocationName, "is_demo": !isPro]
            )
        }
    }

    private func updateUserMessage() {
        userMessage = actionMessage ?? vpnMessage ?? locationMessage
    }

}
