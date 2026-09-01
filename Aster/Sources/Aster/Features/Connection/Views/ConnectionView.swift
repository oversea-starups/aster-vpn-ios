import SwiftUI

struct ConnectionView: View {
    @StateObject private var viewModel = ConnectionViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AsterTheme.background.ignoresSafeArea()

                ScrollView {
                    homeLayout(compact: false)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $viewModel.showsPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $viewModel.showsLocations) {
                LocationsView(canSwitchLocation: viewModel.canSwitchLocation)
            }
            .task {
                await viewModel.refreshLocationsIfNeeded()
            }
        }
    }

    private func homeLayout(compact: Bool) -> some View {
        VStack(spacing: compact ? 16 : 24) {
            brandHeader
            statusHero(compact: compact)
            locationCard

            // Keep the free-access status visible for every non-Pro user. A
            // one-time allowance can be exhausted, but hiding the card makes
            // the account state look broken and removes the path to upgrade.
            if !viewModel.isPro {
                freeExperienceCard
            }

            if let message = viewModel.userMessage {
                messageCard(message)
            }

            accessHubCard(compact: compact)
        }
        .padding(.horizontal, compact ? 16 : 20)
        .padding(.vertical, compact ? 16 : 24)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var brandHeader: some View {
        HStack {
            Label {
                Text("Aster")
                    .font(.title3.weight(.bold))
            } icon: {
                Image(systemName: "asterisk")
                    .foregroundStyle(AsterTheme.cyan)
            }

            Spacer()

            if viewModel.isPro {
                Text("PRO")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AsterTheme.navy)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(AsterTheme.mint, in: Capsule())
            }
        }
        .padding(.top, 8)
    }

    private func statusHero(compact: Bool) -> some View {
        VStack(spacing: 10) {
            connectionSwitch(compact: compact)

            VStack(spacing: 5) {
                Text(viewModel.presentationState.title)
                    .font(compact ? .title2.weight(.bold) : .largeTitle.weight(.bold))
                Text(viewModel.presentationState.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func connectionSwitch(compact: Bool) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            viewModel.toggleConnection()
        } label: {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.13))
                    .frame(width: compact ? 136 : 154, height: compact ? 136 : 154)
                Circle()
                    .stroke(statusColor.opacity(0.22), lineWidth: 1)
                    .frame(width: compact ? 116 : 132, height: compact ? 116 : 132)
                Circle()
                    .fill(primaryActionColor)
                    .frame(width: compact ? 92 : 104, height: compact ? 92 : 104)
                    .shadow(color: primaryActionColor.opacity(0.42), radius: 16, y: 6)
                Image(systemName: viewModel.presentationState.symbolName)
                    .font(.system(size: compact ? 32 : 40, weight: .semibold))
                    .foregroundStyle(AsterTheme.navy)
            }
            .accessibilityHidden(true)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("connectButton")
        .accessibilityLabel(viewModel.presentationState.isProtected ? "Disconnect VPN" : "Connect VPN")
        .accessibilityValue(viewModel.presentationState.title)
        .accessibilityHint(viewModel.presentationState.isProtected ? "Disconnects the VPN" : "Starts the VPN or opens upgrade options")
        .disabled(!viewModel.isEntitlementReady)
    }

    private func accessHubCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 11 : 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aster Pro")
                        .font(.headline)
                    Text(viewModel.isPro ? "Unlimited protection · No ads" : "Upgrade for unlimited protection")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(viewModel.isPro ? AsterTheme.mint : .white)
                }

                Spacer(minLength: 8)

                Image(systemName: viewModel.isPro ? "infinity" : "lock.shield")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(viewModel.isPro ? AsterTheme.mint : AsterTheme.cyan)
            }

            if !viewModel.isPro {
                Button("Upgrade to Pro") {
                    viewModel.showsPaywall = true
                }
                .accessibilityIdentifier("showPaywallButton")
                .font(.body.weight(.bold))
                .foregroundStyle(AsterTheme.navy)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AsterTheme.mint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        .padding(18)
        .background(accessSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    viewModel.isPro ? AsterTheme.mint.opacity(0.55) : AsterTheme.mint.opacity(0.48),
                    lineWidth: 1.5
                )
        }
    }

    private var accessSurface: AnyShapeStyle {
        if viewModel.isPro {
            return AnyShapeStyle(AsterTheme.deepBlue)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [AsterTheme.mint.opacity(0.20), AsterTheme.deepBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var locationCard: some View {
        Button {
            viewModel.showsLocations = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: viewModel.hasSelectedLocation ? "location.circle.fill" : "location.circle")
                    .font(.title2)
                    .foregroundStyle(viewModel.hasSelectedLocation ? AsterTheme.mint : AsterTheme.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Location")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(viewModel.selectedLocationName)
                        .font(.body.weight(.bold))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(viewModel.canSwitchLocation ? "Change" : "View")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AsterTheme.cyan)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .asterCard()
        .accessibilityIdentifier("locationPickerButton")
        .accessibilityHint(
            viewModel.canSwitchLocation
                ? "Opens regions"
                : "Disconnect before changing regions"
        )
    }

    private func messageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(AsterTheme.warning)
            HStack {
                if viewModel.presentationState == .unavailable {
                    Button("Try again") { viewModel.retryVPNSetup() }
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button("Dismiss") { viewModel.dismissMessage() }
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
        }
        .asterCard()
    }

    private var freeExperienceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(AsterTheme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(freeExperienceTitle)
                    .font(.subheadline.weight(.semibold))
                Text(freeExperienceDetail)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
        }
        .asterCard()
        .accessibilityIdentifier("freeExperienceCard")
    }

    private var freeExperienceTitle: String {
        if viewModel.freeExperienceRemainingSeconds > 0 {
            return "Free protection"
        }
        return viewModel.freeExperienceHasBeenClaimed ? "Free time used" : "10 minutes included"
    }

    private var freeExperienceDetail: String {
        if viewModel.freeExperienceRemainingSeconds > 0 {
            return "\(viewModel.formattedFreeExperienceRemaining) remaining"
        }
        if viewModel.freeExperienceHasBeenClaimed {
            return "Upgrade to Pro for unlimited protection."
        }
        return "Your first connection includes 10 minutes of protection."
    }

    private var statusColor: Color {
        switch viewModel.presentationState {
        case .protected: return AsterTheme.mint
        case .connecting, .verifying, .disconnecting, .reconnecting: return AsterTheme.cyan
        case .unavailable: return AsterTheme.warning
        case .disconnected: return .white.opacity(0.75)
        }
    }

    private var primaryActionColor: Color {
        switch viewModel.presentationState {
        case .protected: return AsterTheme.mint
        case .unavailable: return AsterTheme.warning
        case .disconnected: return .white
        case .connecting, .verifying, .disconnecting, .reconnecting: return AsterTheme.cyan
        }
    }
}
