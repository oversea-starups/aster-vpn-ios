import SwiftUI

struct VPNDataUseDisclosureView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            AsterTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AsterTheme.mint)
                            .accessibilityHidden(true)
                        Text("Before you connect")
                            .font(.largeTitle.weight(.bold))
                            .accessibilityIdentifier("privacyDisclosureTitle")
                        Text("Here’s what happens when you use Aster.")
                            .font(.body)
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 14) {
                        disclosureRow(
                            icon: "network.badge.shield.half.filled",
                            title: "VPN connection",
                            detail: "When Aster is connected, your internet activity is routed through the location you choose. We don’t log the websites you visit or what you do online."
                        )
                        disclosureRow(
                            icon: "iphone",
                            title: "On this device",
                            detail: "Your chosen location and remaining free time stay on this iPhone so Aster can work as expected."
                        )
                        disclosureRow(
                            icon: "creditcard.fill",
                            title: "Subscriptions",
                            detail: "Apple handles payments. Your subscription unlocks Aster Pro."
                        )
                    }
                    .asterCard()

                    HStack(spacing: 20) {
                        if let privacyURL = AppConfiguration.privacyPolicyURL {
                            Link("Privacy Policy", destination: privacyURL)
                        }
                        Link(
                            "Terms of Use",
                            destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                        )
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)

                    Button("Continue") {
                        onContinue()
                    }
                    .font(.headline)
                    .foregroundStyle(AsterTheme.navy)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(AsterTheme.mint, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .accessibilityIdentifier("acceptPrivacyDisclosureButton")
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private func disclosureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AsterTheme.cyan)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
