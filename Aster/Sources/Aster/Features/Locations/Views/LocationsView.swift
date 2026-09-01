import StoreKit
import SwiftUI

struct LocationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = NodeCatalogStore.shared
    @StateObject private var subscriptionStore = SubscriptionStore.shared
    @State private var selectedSection: LocationsSection = .vip
    @State private var selectedProductID: String? = AppConfiguration.yearlyProductID
    let canSwitchLocation: Bool
    let showsCloseButton: Bool

    init(canSwitchLocation: Bool, showsCloseButton: Bool = true) {
        self.canSwitchLocation = canSwitchLocation
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AsterTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        sectionPicker
                        if selectedSection == .vip {
                            vipPlans
                        } else {
                            locationsContent
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .task {
                await store.refreshIfNeeded()
            }
        }
    }

    private enum LocationsSection: Hashable {
        case vip
        case locations
    }

    private var sectionPicker: some View {
        Picker("Access", selection: $selectedSection) {
            Text("VIP").tag(LocationsSection.vip)
            Text("Locations").tag(LocationsSection.locations)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("locationSectionPicker")
    }

    private var vipPlans: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aster Pro")
                    .font(.title2.weight(.bold))
                Text("Unlimited protection without ads, timers, or interruptions.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                if subscriptionStore.products.isEmpty {
                    Text(subscriptionStore.isLoading ? "Loading plans…" : "Plans are temporarily unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(subscriptionStore.products, id: \.id) { product in
                        Button {
                            selectedProductID = product.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedProductID == product.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedProductID == product.id ? AsterTheme.mint : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(product.displayName)
                                        .font(.headline)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 8)
                                Text(product.displayPrice)
                                    .font(.headline)
                            }
                            .padding(14)
                            .background(
                                selectedProductID == product.id ? AsterTheme.mint.opacity(0.10) : .white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        selectedProductID == product.id ? AsterTheme.mint : .white.opacity(0.10),
                                        lineWidth: 1.5
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selectedProductID == product.id ? "Selected" : "Not selected")
                    }
                }
            }

            if let selectedProduct {
                Button {
                    Task { _ = await subscriptionStore.purchase(selectedProduct) }
                } label: {
                    HStack(spacing: 10) {
                        if subscriptionStore.isLoading {
                            ProgressView().tint(AsterTheme.navy)
                        }
                        Text(purchaseTitle(for: selectedProduct))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AsterTheme.navy)
                .background(AsterTheme.mint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .disabled(subscriptionStore.isLoading)
                .accessibilityIdentifier("vipPurchaseButton")
            }

            if let message = subscriptionStore.userMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(AsterTheme.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .asterCard()
        .task {
            if subscriptionStore.products.isEmpty {
                await subscriptionStore.loadProducts()
            }
        }
        .onChange(of: subscriptionStore.products.map(\.id)) { productIDs in
            guard let first = productIDs.first else { return }
            if selectedProductID == nil || !productIDs.contains(selectedProductID ?? "") {
                selectedProductID = productIDs.first(where: { $0 == AppConfiguration.yearlyProductID }) ?? first
            }
        }
    }

    private var selectedProduct: Product? {
        subscriptionStore.products.first(where: { $0.id == selectedProductID }) ?? subscriptionStore.products.first
    }

    private func purchaseTitle(for product: Product) -> String {
        guard
            subscriptionStore.freeTrialEligibleProductIDs.contains(product.id),
            let period = product.subscription?.introductoryOffer?.period
        else {
            return "Subscribe with Apple"
        }

        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return "Start a \(period.value)-\(unit) free trial"
    }

    private var locationsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !canSwitchLocation {
                Label(
                    "Disconnect before switching locations.",
                    systemImage: "info.circle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .asterCard()
            }

            if let message = store.userMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AsterTheme.warning)
                    if store.hasUpdateSource {
                        Button("Try Again") {
                            Task { await store.refresh() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(store.isRefreshing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .asterCard()
            }

            if store.nodes.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(displayNodes) { node in
                        locationRow(node)
                    }
                }
            }

            updateFooter
        }
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 38))
                .foregroundStyle(AsterTheme.cyan)
            Text("Locations are temporarily unavailable")
                .font(.headline)
            Text("Check your internet connection, then try again.")
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if store.hasUpdateSource {
                Button("Refresh Locations") {
                    Task { await store.refresh() }
                }
                .font(.body.weight(.bold))
                .foregroundStyle(AsterTheme.navy)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AsterTheme.mint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .disabled(store.isRefreshing)
            }
        }
        .frame(maxWidth: .infinity)
        .asterCard()
    }

    private func locationRow(_ node: VPNNode) -> some View {
        let isSelected = store.selectedNodeID == node.id
        return Button {
            guard canSwitchLocation else { return }
            if store.select(node) {
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "location.circle.fill" : "location.circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AsterTheme.mint : AsterTheme.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text(node.regionName)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(isSelected ? "Selected" : "Use this region")
                        .font(.caption)
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AsterTheme.mint)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(
                isSelected ? AsterTheme.mint.opacity(0.12) : .white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AsterTheme.mint : .white.opacity(0.10), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSwitchLocation)
        .accessibilityIdentifier("location_\(node.id)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var displayNodes: [VPNNode] {
        var nodesByRegion: [String: VPNNode] = [:]
        var regionOrder: [String] = []

        for node in store.nodes {
            let region = node.regionName
            if nodesByRegion[region] == nil {
                regionOrder.append(region)
                nodesByRegion[region] = node
            }
            if node.id == store.selectedNodeID {
                nodesByRegion[region] = node
            }
        }

        return regionOrder.compactMap { nodesByRegion[$0] }
    }

    private var updateFooter: some View {
        HStack(spacing: 10) {
            if store.isRefreshing {
                ProgressView().tint(AsterTheme.cyan)
                Text("Updating locations…")
            } else if let lastUpdated = store.lastUpdated {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AsterTheme.mint)
                Text("Updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(AsterTheme.cyan)
                Text("Using your saved location")
            }

            Spacer(minLength: 0)

            if store.hasUpdateSource && !store.isRefreshing {
                Button("Refresh") {
                    Task { await store.refresh() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .font(.footnote)
        .foregroundStyle(.white)
    }
}
