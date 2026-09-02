import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SubscriptionStore.shared
    @State private var selectedProductID = AppConfiguration.yearlyProductID

    var body: some View {
        NavigationStack {
            ZStack {
                AsterTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 58))
                            .foregroundStyle(AsterTheme.mint)

                        VStack(spacing: 8) {
                            Text("Protection without limits")
                                .font(.largeTitle.weight(.bold))
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("paywallTitle")
                            Text("Keep Aster on without ads, timers, or interruptions.")
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 14) {
                            feature("infinity", "Unlimited VPN time")
                            feature("rectangle.slash", "No ads")
                            feature("arrow.clockwise", "Continuous protection when you need it")
                        }
                        .asterCard()

                        if store.isLoading && store.products.isEmpty {
                            loadingPlans
                        } else if store.products.isEmpty {
                            unavailablePlans
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.products, id: \.id) { product in
                                    SubscriptionPlanCard(
                                        product: product,
                                        isSelected: selectedProductID == product.id,
                                        isBestValue: isBestValue(product),
                                        onSelect: { selectedProductID = product.id }
                                    )
                                }
                            }
                            SubscriptionPurchaseButton(
                                product: selectedProduct,
                                isLoading: store.isLoading,
                                eligibleProductIDs: store.freeTrialEligibleProductIDs,
                                action: {
                                    guard let product = selectedProduct else { return }
                                    Task { _ = await store.purchase(product) }
                                }
                            )
                        }

                        Button("Restore Purchases") {
                            Task { await store.restorePurchases() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(store.isLoading)

                        if let message = store.userMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(AsterTheme.warning)
                                .multilineTextAlignment(.center)
                        }

                        legal
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 36)
                }
            }
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: store.isPro) { isPro in
                if isPro { dismiss() }
            }
            .onChange(of: store.products.map(\.id)) { productIDs in
                if !productIDs.contains(selectedProductID), let first = productIDs.first {
                    selectedProductID = first
                }
            }
            .task {
                await store.reloadProductsIfNeeded()
                AsterAnalytics.log(AsterAnalytics.Event.paywallView, parameters: ["source": "open"])
            }
        }
    }

    private var unavailablePlans: some View {
        VStack(spacing: 12) {
            Text("Plans are temporarily unavailable.")
                .font(.headline)
            Button("Try Again") {
                Task { await store.loadProducts() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .asterCard()
    }

    private var loadingPlans: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading subscription options…")
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .asterCard()
        .accessibilityIdentifier("loadingSubscriptionOptions")
    }

    private var selectedProduct: Product? {
        store.products.first(where: { $0.id == selectedProductID }) ?? store.products.first
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Text(subscriptionDisclosure)
                .font(.caption2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                Link(
                    "Terms",
                    destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                )
                if let privacyURL = AppConfiguration.privacyPolicyURL {
                    Link("Privacy", destination: privacyURL)
                }
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var subscriptionDisclosure: String {
        guard let product = selectedProduct else {
            return "Subscription terms and price appear after the App Store loads available options."
        }

        let renewalPeriod = product.subscription.map {
            Self.renewalPeriodText($0.subscriptionPeriod)
        } ?? "billing period"
        if let trialPeriod = eligibleFreeTrialPeriod(for: product) {
            return "Your \(Self.periodText(trialPeriod, hyphenated: false)) free trial starts today. Unless canceled at least 24 hours before it ends, your Apple ID will be charged \(product.displayPrice) per \(renewalPeriod), and the subscription will renew automatically. Manage or cancel it in Apple ID settings."
        }
        return "Your Apple ID will be charged \(product.displayPrice) at confirmation. The subscription renews automatically every \(renewalPeriod) at the displayed price unless canceled at least 24 hours before the current period ends. Manage or cancel it in Apple ID settings."
    }

    private func eligibleFreeTrialPeriod(for product: Product) -> Product.SubscriptionPeriod? {
        guard store.freeTrialEligibleProductIDs.contains(product.id) else { return nil }
        return product.subscription?.introductoryOffer?.period
    }

    private func isBestValue(_ product: Product) -> Bool {
        SubscriptionPlanPresentation.isBestValue(
            product,
            products: store.products
        )
    }

    static func yearlyPlanIsBetterValue(yearlyPrice: Decimal, monthlyPrice: Decimal) -> Bool {
        SubscriptionPlanPresentation.yearlyPlanIsBetterValue(
            yearlyPrice: yearlyPrice,
            monthlyPrice: monthlyPrice
        )
    }

    private static func periodText(
        _ period: Product.SubscriptionPeriod,
        hyphenated: Bool
    ) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        let pluralizedUnit = period.value == 1 ? unit : "\(unit)s"
        return hyphenated
            ? "\(period.value)-\(pluralizedUnit)"
            : "\(period.value) \(pluralizedUnit)"
    }

    private static func renewalPeriodText(_ period: Product.SubscriptionPeriod) -> String {
        guard period.value == 1 else {
            return periodText(period, hyphenated: false)
        }
        switch period.unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "billing period"
        }
    }

    private func feature(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(AsterTheme.cyan)
                .frame(width: 24)
            Text(title).font(.subheadline)
            Spacer()
        }
    }
}
