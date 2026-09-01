import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var products: [Product] = []
    @Published private(set) var freeTrialEligibleProductIDs: Set<String> = []
    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var isPro = false
    @Published private(set) var expirationDate: Date?
    @Published private(set) var activeProductID: String?
    @Published private(set) var isEntitlementReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var userMessage: String?

    private let productIDs: Set<String>
    private var updatesTask: Task<Void, Never>?
    private var entitlementReadinessTask: Task<Void, Never>?

    init(productIDs: Set<String> = Set(AppConfiguration.subscriptionProductIDs)) {
        self.productIDs = productIDs
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }

        Task { await loadProducts() }
        Task { await refreshEntitlements() }
        entitlementReadinessTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, !self.isEntitlementReady else { return }

            // StoreKit's local entitlement sequence can occasionally stall. Do not
            // block free access indefinitely or grant Pro without a verified transaction.
            self.isEntitlementReady = true
        }
    }

    deinit {
        updatesTask?.cancel()
        entitlementReadinessTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await Product.products(for: productIDs)
            let sortedProducts = loaded.sorted { lhs, rhs in
                if lhs.id == AppConfiguration.yearlyProductID { return true }
                if rhs.id == AppConfiguration.yearlyProductID { return false }
                return lhs.price < rhs.price
            }
            var eligibleProductIDs = Set<String>()
            for product in sortedProducts {
                guard
                    let subscription = product.subscription,
                    subscription.introductoryOffer?.paymentMode == .freeTrial,
                    await subscription.isEligibleForIntroOffer
                else {
                    continue
                }
                eligibleProductIDs.insert(product.id)
            }

            products = sortedProducts
            freeTrialEligibleProductIDs = eligibleProductIDs
            userMessage = loaded.isEmpty ? "Subscriptions aren't available right now." : nil
        } catch {
            products = []
            freeTrialEligibleProductIDs = []
            userMessage = "Subscriptions aren't available right now. Please try again later."
        }
    }

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        userMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    userMessage = "We couldn't verify this purchase. You weren't charged by Aster."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .pending:
                userMessage = "Your purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                userMessage = "The purchase couldn't be completed. Please try again."
                return false
            }
        } catch {
            userMessage = "The purchase couldn't be completed. Please try again."
            return false
        }
    }

    func restorePurchases() async {
        isLoading = true
        userMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                userMessage = "No active Aster subscription was found for this Apple ID."
            }
        } catch {
            userMessage = "Purchases couldn't be restored. Please check your Apple ID and try again."
        }
    }

    func refreshEntitlements() async {
        var activeTransaction: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID), transaction.revocationDate == nil else { continue }
            if let expirationDate = transaction.expirationDate, expirationDate <= Date() { continue }
            if activeTransaction == nil ||
                (transaction.expirationDate ?? .distantFuture) > (activeTransaction?.expirationDate ?? .distantFuture) {
                activeTransaction = transaction
            }
        }

        tier = activeTransaction.flatMap { AppConfiguration.subscriptionTier(for: $0.productID) } ?? .free
        isPro = tier.hasUnlimitedProtection
        expirationDate = activeTransaction?.expirationDate
        activeProductID = activeTransaction?.productID
        isEntitlementReady = true
        entitlementReadinessTask?.cancel()
    }
}
