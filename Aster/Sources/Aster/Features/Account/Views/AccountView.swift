import SwiftUI

struct AccountView: View {
    @StateObject private var subscriptionStore = SubscriptionStore.shared
    @State private var showsPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                AsterTheme.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showsPaywall) {
                PaywallView()
            }
        }
    }

    private var content: some View {
        ViewThatFits(in: .vertical) {
            accountLayout(compact: false)
            accountLayout(compact: true)
            ScrollView {
                accountLayout(compact: true)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func accountLayout(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            planCard
            accountActions
            legalActions
        }
        .padding(.horizontal, compact ? 16 : 20)
        .padding(.vertical, compact ? 12 : 20)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: subscriptionStore.isPro ? "crown.fill" : "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(subscriptionStore.isPro ? AsterTheme.mint : AsterTheme.cyan)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionStore.tier.displayName)
                        .font(.title3.weight(.bold))
                    Text(subscriptionStore.isPro ? "Active" : "Free access")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(subscriptionStore.isPro ? AsterTheme.mint : .white)
                }

                Spacer(minLength: 8)

                if subscriptionStore.isPro {
                    Text("PRO")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(AsterTheme.navy)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AsterTheme.mint, in: Capsule())
                }
            }

            if subscriptionStore.isPro {
                Text(subscriptionDateText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text("Unlimited · Ad-free")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AsterTheme.mint)
            } else {
                Text("Upgrade for unlimited protection.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Upgrade to Pro") {
                    showsPaywall = true
                }
                .font(.body.weight(.bold))
                .foregroundStyle(AsterTheme.navy)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AsterTheme.mint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityIdentifier("accountUpgradeButton")
            }
        }
        .padding(18)
        .background(
            subscriptionStore.isPro ? AsterTheme.deepBlue : AsterTheme.deepBlue.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(subscriptionStore.isPro ? AsterTheme.mint.opacity(0.65) : AsterTheme.cyan.opacity(0.30), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    private var accountActions: some View {
        VStack(spacing: 0) {
            Button {
                Task { await subscriptionStore.restorePurchases() }
            } label: {
                actionRow(icon: "arrow.clockwise", title: "Restore purchases", detail: nil)
            }
            .buttonStyle(.plain)
            .disabled(subscriptionStore.isLoading)
            .accessibilityIdentifier("accountRestorePurchasesButton")

            Divider().overlay(.white.opacity(0.12))

            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                actionRow(icon: "creditcard", title: "Manage subscription", detail: nil)
            }
            .accessibilityIdentifier("accountManageSubscriptionLink")
        }
        .padding(.horizontal, 16)
        .background(AsterTheme.deepBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var legalActions: some View {
        VStack(spacing: 0) {
            Link(
                destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
            ) {
                actionRow(icon: "doc.text", title: "Terms of use", detail: nil)
            }
            .accessibilityIdentifier("accountTermsLink")

            if let privacyURL = AppConfiguration.privacyPolicyURL {
                Divider().overlay(.white.opacity(0.12))
                Link(destination: privacyURL) {
                    actionRow(icon: "lock.shield", title: "Privacy policy", detail: nil)
                }
                .accessibilityIdentifier("accountPrivacyPolicyLink")
            }
        }
        .padding(.horizontal, 16)
        .background(AsterTheme.deepBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func actionRow(icon: String, title: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AsterTheme.cyan)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var subscriptionDateText: String {
        guard let expirationDate = subscriptionStore.expirationDate else {
            return "Subscription active"
        }
        return "Access through \(expirationDate.formatted(date: .abbreviated, time: .omitted))"
    }

}
