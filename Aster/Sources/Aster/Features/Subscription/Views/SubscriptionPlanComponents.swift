import StoreKit
import SwiftUI

/// Shared subscription plan presentation used by both the full-screen paywall
/// and the VIP section inside the Locations tab. Keeping the option and CTA
/// here prevents the two purchase entry points from drifting visually or in
/// their user-facing copy.
struct SubscriptionPlanCard: View {
    let product: Product
    let isSelected: Bool
    let isBestValue: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AsterTheme.mint : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.headline)
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(AsterTheme.navy)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(AsterTheme.mint, in: Capsule())
                        }
                    }
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                Spacer()
                Text(product.displayPrice)
                    .font(.headline)
            }
            .padding(16)
            .background(
                isSelected ? AsterTheme.mint.opacity(0.10) : .white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? AsterTheme.mint : .white.opacity(0.10),
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct SubscriptionPurchaseButton: View {
    let product: Product?
    let isLoading: Bool
    let eligibleProductIDs: Set<String>
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(AsterTheme.navy)
                }
                Text(Self.purchaseTitle(for: product, eligibleProductIDs: eligibleProductIDs))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AsterTheme.navy)
        .background(AsterTheme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(isLoading || product == nil)
    }

    static func purchaseTitle(for product: Product?, eligibleProductIDs: Set<String>) -> String {
        guard let product else { return "Choose a plan" }
        guard
            eligibleProductIDs.contains(product.id),
            let period = product.subscription?.introductoryOffer?.period
        else {
            return "Unlock unlimited protection"
        }
        return "Start \(periodText(period, hyphenated: true)) free trial"
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
}

enum SubscriptionPlanPresentation {
    static func isBestValue(_ product: Product, products: [Product]) -> Bool {
        guard
            product.id == AppConfiguration.yearlyProductID,
            let monthly = products.first(where: { $0.id == AppConfiguration.monthlyProductID })
        else {
            return false
        }
        return yearlyPlanIsBetterValue(yearlyPrice: product.price, monthlyPrice: monthly.price)
    }

    static func yearlyPlanIsBetterValue(yearlyPrice: Decimal, monthlyPrice: Decimal) -> Bool {
        yearlyPrice < monthlyPrice * 12
    }
}
