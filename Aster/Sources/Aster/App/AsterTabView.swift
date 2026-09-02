import NetworkExtension
import SwiftUI

struct AsterTabView: View {
    private enum AppTab: Hashable {
        case home
        case vip
        case account
    }

    @State private var selectedTab: AppTab = .home
    @State private var locationsTabGeneration = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(AppTab.home)
                .accessibilityIdentifier("homeTab")

            LocationsTabView()
                .id(locationsTabGeneration)
                .tabItem {
                    Label("VIP", systemImage: "sparkles")
                }
                .tag(AppTab.vip)
                .accessibilityIdentifier("locationsTab")

            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .tag(AppTab.account)
                .accessibilityIdentifier("accountTab")
        }
        .tint(AsterTheme.cyan)
        .preferredColorScheme(.dark)
        .onChange(of: selectedTab) { tab in
            guard tab == .vip else { return }
            locationsTabGeneration += 1
        }
    }
}

private struct LocationsTabView: View {
    @StateObject private var vpnManager = VPNManager.shared

    private var canSwitchLocation: Bool {
        vpnManager.status == .disconnected || vpnManager.status == .invalid
    }

    var body: some View {
        LocationsView(
            canSwitchLocation: canSwitchLocation,
            showsCloseButton: false,
            initialSection: .vip
        )
    }
}
