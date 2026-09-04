import StoreKit
import SwiftUI
import UIKit

struct StoreProductOffering: Identifiable {
    let catalogItem: AppStoreCatalogItem
    let product: Product

    var id: String { product.id }
}

enum StorePurchasePhase: Equatable {
    case idle
    case loading
    case purchasing(productID: String)
    case restoring
    case managing

    var isBusy: Bool {
        self != .idle
    }
}

/// Coordinates StoreKit 2 with the server's JWS-verification endpoints.
///
/// A verified local transaction is never treated as an entitlement by itself:
/// it is finished only after the authenticated backend accepts its signed JWS.
@MainActor
final class StoreKitPurchaseCoordinator: ObservableObject {
    @Published private(set) var offerings: [StoreProductOffering] = []
    @Published private(set) var entitlement: AppStoreEntitlementSnapshot?
    @Published private(set) var phase: StorePurchasePhase = .idle
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let api: any StoreKitAPIProviding
    private let accountProvider: any StoreKitAccountProviding
    private let authenticationFailureHandler: (Error) -> Void
    private let entitlementChangedHandler: @MainActor () async -> Void
    private var transactionUpdatesTask: Task<Void, Never>?
    private var operationGeneration = UUID()

    init(
        api: any StoreKitAPIProviding,
        accountProvider: any StoreKitAccountProviding,
        authenticationFailureHandler: @escaping (Error) -> Void = { _ in },
        entitlementChangedHandler: @escaping @MainActor () async -> Void = {}
    ) {
        self.api = api
        self.accountProvider = accountProvider
        self.authenticationFailureHandler = authenticationFailureHandler
        self.entitlementChangedHandler = entitlementChangedHandler
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var hasServerAuthorizedAccess: Bool {
        entitlement?.grantsAccess == true
    }

    func activate() async {
        startObservingTransactionUpdates()
        await load(reconcileUnfinishedTransactions: true)
    }

    func load() async {
        await load(reconcileUnfinishedTransactions: false)
    }

    private func load(reconcileUnfinishedTransactions: Bool) async {
        guard !phase.isBusy else { return }
        let generation = operationGeneration
        phase = .loading
        errorMessage = nil

        do {
            let account = try await accountProvider.currentStoreKitAccount()
            let reconciledCount: Int
            if reconcileUnfinishedTransactions {
                reconciledCount = try await reconcileUnfinished(
                    account: account,
                    generation: generation
                )
            } else {
                reconciledCount = 0
            }
            let loadedOfferings = try await fetchCatalog()
            try await validate(account: account, generation: generation)
            let snapshot = try await fetchEntitlement(
                account: account,
                generation: generation
            )
            offerings = loadedOfferings
            entitlement = snapshot
            if reconciledCount > 0 {
                statusMessage = "已补偿同步 \(reconciledCount) 笔待处理订阅。"
                await entitlementChangedHandler()
            }
        } catch {
            present(error, generation: generation)
        }

        finishOperation(generation)
    }

    func purchase(_ offering: StoreProductOffering) async {
        guard !phase.isBusy else { return }
        let generation = operationGeneration
        phase = .purchasing(productID: offering.id)
        errorMessage = nil
        statusMessage = nil

        do {
            let account = try await accountProvider.currentStoreKitAccount()
            let purchaseResult = try await offering.product.purchase(
                options: [.appAccountToken(account.userID)]
            )
            try await validate(account: account, generation: generation)

            switch purchaseResult {
            case let .success(verification):
                _ = try await syncVerifiedTransaction(
                    verification,
                    account: account,
                    generation: generation
                )
                let snapshot = try await fetchEntitlement(
                    account: account,
                    generation: generation
                )
                entitlement = snapshot
                statusMessage = "订阅已购买并同步到 ClashX VPN。"
                await entitlementChangedHandler()
            case .pending:
                statusMessage = "购买正在等待 Apple 或家庭组织者批准。"
            case .userCancelled:
                break
            @unknown default:
                statusMessage = "App Store 返回了新的购买状态，请稍后刷新。"
            }
        } catch {
            present(error, generation: generation)
        }

        finishOperation(generation)
    }

    /// User-initiated restore. AppStore.sync may show an Apple sign-in sheet,
    /// so this method must only be called from an explicit button action.
    func restorePurchases() async {
        guard !phase.isBusy else { return }
        let generation = operationGeneration
        phase = .restoring
        errorMessage = nil
        statusMessage = nil

        do {
            let account = try await accountProvider.currentStoreKitAccount()
            try await AppStore.sync()
            try await validate(account: account, generation: generation)

            var successfulSyncs = 0
            var encounteredFailure = false
            var authenticationFailure: Error?

            for await verification in StoreKit.Transaction.currentEntitlements {
                do {
                    _ = try await syncVerifiedTransaction(
                        verification,
                        account: account,
                        generation: generation
                    )
                    successfulSyncs += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if (error as? APIClientError)?.isAuthenticationFailure == true {
                        authenticationFailure = error
                        break
                    }
                    encounteredFailure = true
                }
            }

            if let authenticationFailure {
                throw authenticationFailure
            }
            if encounteredFailure {
                throw AsterStorePurchaseError.restoreIncomplete(
                    successful: successfulSyncs
                )
            }

            let snapshot = try await fetchEntitlement(
                account: account,
                generation: generation
            )
            entitlement = snapshot
            statusMessage = successfulSyncs > 0
                ? "已恢复并同步 \(successfulSyncs) 笔有效订阅。"
                : "当前 Apple ID 没有可恢复的有效订阅。"
            await entitlementChangedHandler()
        } catch {
            present(error, generation: generation)
        }

        finishOperation(generation)
    }

    func showManageSubscriptions(in scene: UIWindowScene?) async {
        guard !phase.isBusy else { return }
        guard let scene else {
            present(
                AsterStorePurchaseError.unavailableWindowScene,
                generation: operationGeneration
            )
            return
        }

        let generation = operationGeneration
        phase = .managing
        errorMessage = nil
        statusMessage = nil
        do {
            let account = try await accountProvider.currentStoreKitAccount()
            try await AppStore.showManageSubscriptions(in: scene)
            let snapshot = try await fetchEntitlement(
                account: account,
                generation: generation
            )
            entitlement = snapshot
            await entitlementChangedHandler()
        } catch {
            present(error, generation: generation)
        }
        finishOperation(generation)
    }

    func clearError() {
        errorMessage = nil
    }

    func clearStatusMessage() {
        statusMessage = nil
    }

    func deactivate() {
        operationGeneration = UUID()
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = nil
        offerings = []
        entitlement = nil
        phase = .idle
        statusMessage = nil
        errorMessage = nil
    }

    private func fetchCatalog() async throws -> [StoreProductOffering] {
        // Fetch the backend allowlist before asking StoreKit for products.
        let catalog = try await api.fetchAllowedProducts()
        let allowedProductIDs = Array(Set(catalog.map(\.productId)))
        guard !allowedProductIDs.isEmpty else {
            throw AsterStorePurchaseError.noProductsConfigured
        }

        let storeProducts = try await Product.products(for: allowedProductIDs)
        let productsByID = Dictionary(
            uniqueKeysWithValues: storeProducts.map { ($0.id, $0) }
        )
        let loadedOfferings: [StoreProductOffering] = catalog.compactMap {
            item -> StoreProductOffering? in
            guard let product = productsByID[item.productId],
                  product.type == .autoRenewable else {
                return nil
            }
            return StoreProductOffering(catalogItem: item, product: product)
        }
        guard !loadedOfferings.isEmpty else {
            throw AsterStorePurchaseError.noProductsConfigured
        }
        return loadedOfferings
    }

    private func fetchEntitlement(
        account: StoreKitAccountContext,
        generation: UUID
    ) async throws -> AppStoreEntitlementSnapshot {
        let snapshot = try await api.fetchEntitlement()
        try await validate(account: account, generation: generation)
        guard snapshot.appAccountToken == account.userID else {
            throw AsterStorePurchaseError.backendAccountMismatch
        }
        return snapshot
    }

    private func syncVerifiedTransaction(
        _ verification: VerificationResult<StoreKit.Transaction>,
        account: StoreKitAccountContext,
        generation: UUID
    ) async throws -> AppStoreTransactionSyncResult {
        let transaction: StoreKit.Transaction
        switch verification {
        case let .verified(value):
            transaction = value
        case .unverified:
            throw AsterStorePurchaseError.unverifiedTransaction
        }

        guard let transactionToken = transaction.appAccountToken,
              account.acceptedAppAccountTokens.contains(transactionToken) else {
            throw AsterStorePurchaseError.transactionAccountMismatch
        }
        try await validate(account: account, generation: generation)

        let result = try await api.syncTransaction(
            jwsRepresentation: verification.jwsRepresentation
        )
        try await validate(account: account, generation: generation)
        guard !result.accountInactive else {
            throw AsterStorePurchaseError.inactiveAccount
        }

        // Finish only after the backend has verified and persisted the JWS,
        // and only while the same authenticated app session remains active.
        await transaction.finish()
        return result
    }

    private func reconcileUnfinished(
        account: StoreKitAccountContext,
        generation: UUID
    ) async throws -> Int {
        var successfulSyncs = 0

        for await verification in StoreKit.Transaction.unfinished {
            do {
                _ = try await syncVerifiedTransaction(
                    verification,
                    account: account,
                    generation: generation
                )
                successfulSyncs += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch AsterStorePurchaseError.transactionAccountMismatch {
                // Leave another Aster account's transaction unfinished. It
                // will be retried after that account authenticates.
                continue
            } catch {
                throw error
            }
        }

        return successfulSyncs
    }

    private func startObservingTransactionUpdates() {
        guard transactionUpdatesTask == nil else { return }
        let generation = operationGeneration

        transactionUpdatesTask = Task { [weak self] in
            for await verification in StoreKit.Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                await self.handleTransactionUpdate(
                    verification,
                    generation: generation
                )
            }
        }
    }

    private func handleTransactionUpdate(
        _ verification: VerificationResult<StoreKit.Transaction>,
        generation: UUID
    ) async {
        do {
            guard generation == operationGeneration else {
                throw CancellationError()
            }
            let account = try await accountProvider.currentStoreKitAccount()
            _ = try await syncVerifiedTransaction(
                verification,
                account: account,
                generation: generation
            )
            let snapshot = try await fetchEntitlement(
                account: account,
                generation: generation
            )
            entitlement = snapshot
            statusMessage = "订阅状态已同步。"
            await entitlementChangedHandler()
        } catch {
            // Leave the transaction unfinished so StoreKit can deliver it again
            // after authentication or backend availability is restored.
            present(error, generation: generation)
        }
    }

    private func validate(
        account: StoreKitAccountContext,
        generation: UUID
    ) async throws {
        guard generation == operationGeneration else {
            throw CancellationError()
        }
        let currentAccount = try await accountProvider.currentStoreKitAccount()
        guard generation == operationGeneration,
              currentAccount == account else {
            throw CancellationError()
        }
    }

    private func finishOperation(_ generation: UUID) {
        guard generation == operationGeneration else { return }
        phase = .idle
    }

    private func present(_ error: Error, generation: UUID) {
        guard generation == operationGeneration,
              !(error is CancellationError) else {
            return
        }
        if (error as? APIClientError)?.isAuthenticationFailure == true {
            authenticationFailureHandler(error)
        }
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? "订阅操作失败，请稍后重试。"
    }
}
