import NetworkExtension
import SwiftUI

struct AsterTabView: View {
    var body: some View {
        TabView {
            ConnectionView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .accessibilityIdentifier("homeTab")

            LocationsTabView()
                .tabItem {
                    Label("Locations", systemImage: "globe.americas.fill")
                }
                .accessibilityIdentifier("locationsTab")

            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
                .accessibilityIdentifier("accountTab")
        }
        .tint(AsterTheme.cyan)
        .preferredColorScheme(.dark)
    }
}

private struct LocationsTabView: View {
    @StateObject private var vpnManager = VPNManager.shared

    private var canSwitchLocation: Bool {
        vpnManager.status == .disconnected || vpnManager.status == .invalid
    }

    var body: some View {
        LocationsView(canSwitchLocation: canSwitchLocation, showsCloseButton: false)
    }
}
