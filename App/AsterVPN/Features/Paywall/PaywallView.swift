import StoreKit
import SwiftUI
import UIKit

struct PaywallView: View {
    @ObservedObject private var coordinator: StoreKitPurchaseCoordinator
    let isGuest: Bool
    let requestAccountAssociation: () -> Void

    @MainActor
    init(
        coordinator: StoreKitPurchaseCoordinator,
        isGuest: Bool = false,
        requestAccountAssociation: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        self.isGuest = isGuest
        self.requestAccountAssociation = requestAccountAssociation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if isGuest {
                    guestPurchaseNotice
                }
                entitlementCard

                if coordinator.phase == .loading && coordinator.offerings.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("正在加载 App Store 订阅…")
                        Spacer()
                    }
                    .padding(.vertical, 32)
                } else {
                    ForEach(coordinator.offerings) { offering in
                        productCard(offering)
                    }
                }

                if let statusMessage = coordinator.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                restoreAndManagementActions
                purchaseDisclosure
            }
            .padding(20)
        }
        .navigationTitle("升级订阅")
        .task {
            await coordinator.activate()
        }
        .alert(
            "订阅操作未完成",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        coordinator.clearError()
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                coordinator.clearError()
            }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择适合你的方案")
                .font(.title2.bold())
            Text(
                isGuest
                    ? "无需注册即可购买。付款由 Apple 安全处理，购买后立即为当前游客身份开通权益。"
                    : "付款由 Apple 安全处理。购买成功后，Aster VPN 服务器验证交易并开通权益。"
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var guestPurchaseNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("游客也可以订阅", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text("订阅会保存在当前设备的安全游客身份下。关联邮箱账号后，可在其他设备登录并同步权益。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("关联账号（可稍后）", action: requestAccountAssociation)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var entitlementCard: some View {
        if let subscription = coordinator.entitlement?.subscription {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    coordinator.hasServerAuthorizedAccess ? "当前权益已生效" : "当前权益不可用",
                    systemImage: coordinator.hasServerAuthorizedAccess
                        ? "checkmark.shield.fill"
                        : "exclamationmark.shield"
                )
                .font(.headline)
                .foregroundStyle(coordinator.hasServerAuthorizedAccess ? .green : .orange)

                Text(subscription.planName ?? "Aster VPN 订阅")
                    .font(.subheadline.weight(.semibold))
                Text("剩余流量：\(formattedBytes(subscription.remainingTraffic))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func productCard(_ offering: StoreProductOffering) -> some View {
        let plan = offering.catalogItem.plan

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.headline)
                    if let description = plan.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(
                    "\(offering.product.displayPrice) / \(subscriptionPeriodText(offering))"
                )
                    .font(.title3.bold())
            }

            HStack(spacing: 12) {
                Label("\(plan.traffic) GB", systemImage: "arrow.up.arrow.down")
                Label("\(plan.deviceLimit) 台设备", systemImage: "laptopcomputer.and.iphone")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(plan.features.values, id: \.self) { feature in
                Label(feature, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            Button {
                Task {
                    await coordinator.purchase(offering)
                }
            } label: {
                if coordinator.phase == .purchasing(productID: offering.id) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("使用 \(offering.product.displayPrice) 订阅")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.phase.isBusy)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var restoreAndManagementActions: some View {
        VStack(spacing: 4) {
            Button("恢复购买") {
                Task {
                    await coordinator.restorePurchases()
                }
            }
            .disabled(coordinator.phase.isBusy)

            Button("管理或取消 Apple 订阅") {
                Task {
                    await coordinator.showManageSubscriptions(in: activeWindowScene)
                }
            }
            .disabled(coordinator.phase.isBusy)
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseDisclosure: some View {
        VStack(spacing: 10) {
            Text("订阅会通过你的 Apple ID 自动续期，除非在当前订阅期结束至少 24 小时前取消。你可以随时在 Apple 订阅管理中查看、变更或取消。实际价格和周期以购买确认页为准。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Link(
                    "隐私政策",
                    destination: AppConfiguration.current.privacyPolicyURL
                )
                Link(
                    "服务条款 / EULA",
                    destination: AppConfiguration.current.termsOfServiceURL
                )
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func formattedBytes(_ value: String) -> String {
        guard let bytes = Int64(value) else { return value }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private func subscriptionPeriodText(
        _ offering: StoreProductOffering
    ) -> String {
        guard let period = offering.product.subscription?.subscriptionPeriod else {
            return localizedBackendPeriod(offering.catalogItem.plan.period)
        }

        let unit: String
        switch period.unit {
        case .day:
            unit = "天"
        case .week:
            unit = "周"
        case .month:
            unit = "个月"
        case .year:
            unit = "年"
        @unknown default:
            return localizedBackendPeriod(offering.catalogItem.plan.period)
        }
        return "\(period.value) \(unit)"
    }

    private func localizedBackendPeriod(_ value: String) -> String {
        switch value.lowercased() {
        case "month", "monthly":
            return "1 个月"
        case "year", "yearly", "annual":
            return "1 年"
        default:
            return value
        }
    }
}
