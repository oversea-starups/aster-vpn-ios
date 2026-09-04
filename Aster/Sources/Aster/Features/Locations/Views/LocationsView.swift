import StoreKit
import SwiftUI

enum LocationsSection: Hashable {
    case vip
    case locations
}

struct LocationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = NodeCatalogStore.shared
    @StateObject private var subscriptionStore = SubscriptionStore.shared
    @State private var selectedSection: LocationsSection
    @State private var selectedProductID: String? = AppConfiguration.yearlyProductID
    let canSwitchLocation: Bool
    let showsCloseButton: Bool
    let resetToken: Int?

    init(
        canSwitchLocation: Bool,
        showsCloseButton: Bool = true,
        initialSection: LocationsSection = .vip,
        resetToken: Int? = nil
    ) {
        self.canSwitchLocation = canSwitchLocation
        self.showsCloseButton = showsCloseButton
        self.resetToken = resetToken
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AsterTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sectionPicker
                        if selectedSection == .vip {
                            vipPlans
                        } else {
                            locationsContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .preferredColorScheme(.dark)
            .navigationTitle(selectedSection == .vip ? "VIP" : "Locations")
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
                await store.checkReachabilityIfNeeded()
            }
            .onChange(of: resetToken) { _ in
                guard resetToken != nil else { return }
                selectedSection = .vip
            }
        }
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

            VStack(spacing: 12) {
                if subscriptionStore.products.isEmpty {
                    Text(subscriptionStore.isLoading ? "Loading plans…" : "Plans are temporarily unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(subscriptionStore.products, id: \.id) { product in
                        SubscriptionPlanCard(
                            product: product,
                            isSelected: selectedProductID == product.id,
                            isBestValue: SubscriptionPlanPresentation.isBestValue(
                                product,
                                products: subscriptionStore.products
                            ),
                            onSelect: { selectedProductID = product.id }
                        )
                    }
                }
            }

            if let selectedProduct {
                SubscriptionPurchaseButton(
                    product: selectedProduct,
                    isLoading: subscriptionStore.isLoading,
                    eligibleProductIDs: subscriptionStore.freeTrialEligibleProductIDs,
                    action: {
                        Task { _ = await subscriptionStore.purchase(selectedProduct) }
                    }
                )
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
                            refreshLocations()
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(store.isRefreshing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .asterCard()
            }

            if store.isCheckingReachability {
                checkingState
            } else if store.reachableNodes.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(displayNodes.enumerated()), id: \.element.id) { index, node in
                        locationRow(node, sequence: index + 1)
                    }
                }
            }

            updateFooter
        }
    }

    private var checkingState: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(AsterTheme.cyan)
            Text("Checking available lines…")
                .font(.headline)
            Text("Only lines with a reachable server endpoint are shown.")
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .asterCard()
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
                    refreshLocations()
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

    private func locationRow(_ node: VPNNode, sequence: Int) -> some View {
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

                Text("\(sequence)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(node.regionName)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
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

        for node in store.reachableNodes {
            // Keep separate ports/protocols visible: a region can expose
            // multiple lines and the health check is performed per node.
            let key = "\(node.regionName)-\(node.id)"
            if nodesByRegion[key] == nil {
                regionOrder.append(key)
                nodesByRegion[key] = node
            }
        }

        return regionOrder.compactMap { nodesByRegion[$0] }
    }

    private var updateFooter: some View {
        HStack(spacing: 10) {
            if store.isRefreshing || store.isCheckingReachability {
                ProgressView().tint(AsterTheme.cyan)
                Text(store.isRefreshing ? "Updating locations…" : "Checking locations…")
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
                    refreshLocations()
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .font(.footnote)
        .foregroundStyle(.white)
    }

    private func refreshLocations() {
        Task {
            await store.refresh()
            await store.checkReachabilityIfNeeded(force: true)
        }
    }
}
