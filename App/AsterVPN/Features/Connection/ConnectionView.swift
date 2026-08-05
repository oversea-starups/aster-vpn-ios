import NetworkExtension
import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var vpnManager: VPNManager
    @ObservedObject var nodeStore: NodeStore
    let authenticationPhase: AuthSession.Phase
    let requestAuthentication: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectionHero
                subscriptionCard
                nodeCard

                if !AppConfiguration.current.packetTunnelTransportAvailable {
                    Label(
                        "开发构建：传输内核尚未链接，连接保持失败关闭。",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }

                if let message = nodeStore.errorMessage ?? vpnManager.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    if authenticationPhase == .signedIn {
                        Task {
                            await nodeStore.toggleConnection()
                        }
                    } else {
                        requestAuthentication()
                    }
                } label: {
                    HStack {
                        if vpnManager.isBusy {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(connectionActionTitle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    vpnManager.isBusy
                        || authenticationPhase == .restoring
                        || nodeStore.isLoading
                        || (
                            authenticationPhase == .signedIn
                                && !nodeStore.hasUsableNode
                                && !nodeStore.canStartTrial
                                && !vpnManager.isConfigured
                                && vpnManager.status != .connected
                        )
                )
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("连接")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if authenticationPhase == .signedIn {
                        Task {
                            await nodeStore.load(force: true)
                        }
                    } else {
                        requestAuthentication()
                    }
                } label: {
                    if authenticationPhase == .restoring || nodeStore.isLoading {
                        ProgressView()
                    } else if authenticationPhase == .signedOut {
                        Image(systemName: "person.crop.circle.badge.plus")
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(authenticationPhase == .restoring || nodeStore.isLoading)
                .accessibilityLabel(
                    authenticationPhase == .signedOut ? "登录或注册" : "刷新订阅和节点"
                )
            }
        }
        .task(id: nodeStore.sessionOwnerID) {
            guard nodeStore.sessionOwnerID != nil else { return }
            await nodeStore.load()
        }
        .refreshable {
            if authenticationPhase == .signedIn {
                await nodeStore.load(force: true)
            } else {
                requestAuthentication()
            }
        }
    }

    private var connectionHero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 132, height: 132)
                Image(
                    systemName: vpnManager.status == .connected
                        ? "lock.shield.fill"
                        : "lock.shield"
                )
                .font(.system(size: 62))
                .foregroundStyle(statusColor)
            }

            VStack(spacing: 4) {
                Text(vpnManager.statusDescription)
                    .font(.title2.bold())
                Text(connectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var subscriptionCard: some View {
        if authenticationPhase != .signedIn {
            VStack(alignment: .leading, spacing: 8) {
                Label("无需先注册", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                Text("你可以直接浏览 App；开始连接、获取节点或同步订阅时，再登录并关联账号。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .cardStyle()
        } else if let subscription = nodeStore.subscription,
                  let trial = subscription.trial,
                  !subscription.entitlementSources.contains(where: { $0.source == "app_store" }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("游客免费体验", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text("\(trial.nodeLimit) 条线路")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }

                if trial.status == "trial_pending" {
                    Text("首次连接后开始计时，可完整体验 \(trial.durationSeconds / 60) 分钟。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let expiresAt = trial.expiresAt {
                    Text("试用截止：\(formatDate(expiresAt))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("本机游客试用已经结束，订阅后可继续使用全部线路。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        } else if let subscription = nodeStore.subscription {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(subscription.planName, systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Spacer()
                    Text(subscription.status == "active" ? "有效" : subscription.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(subscription.status == "active" ? .green : .orange)
                }

                ProgressView(
                    value: Double(subscription.usedTraffic),
                    total: max(Double(subscription.totalTraffic), 1)
                )

                HStack {
                    Text("已用 \(formatBytes(subscription.usedTraffic))")
                    Spacer()
                    Text("剩余 \(formatBytes(subscription.remainingTraffic))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let expiredAt = subscription.expiredAt {
                    Text("到期：\(formatDate(expiredAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        } else if nodeStore.isLoading {
            HStack {
                ProgressView()
                Text("正在加载订阅权益…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder
    private var nodeCard: some View {
        if authenticationPhase == .signedIn {
            if nodeStore.canStartTrial {
                nodeCardLabel
            } else {
                NavigationLink {
                    NodePickerView(nodeStore: nodeStore)
                } label: {
                    nodeCardLabel
                }
                .buttonStyle(.plain)
                .disabled(nodeStore.nodes.isEmpty)
            }
        } else {
            Button(action: requestAuthentication) {
                nodeCardLabel
            }
            .buttonStyle(.plain)
            .disabled(authenticationPhase == .restoring)
        }
    }

    private var nodeCardLabel: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(nodeStore.selectedNode?.name ?? "选择节点")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let node = nodeStore.selectedNode {
                    Text(
                        "\(node.region) · \(node.normalizedProtocol.uppercased())"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        nodeStore.canStartTrial
                            ? "首次连接后获取 2 条体验线路"
                            : authenticationPhase == .signedIn
                                ? "开通有效订阅后可获取节点"
                                : "连接时登录并获取可用节点"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
            if !nodeStore.canStartTrial {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
    }

    private var connectionActionTitle: String {
        if vpnManager.isBusy {
            return "处理中…"
        }
        switch authenticationPhase {
        case .restoring:
            return "正在恢复账号…"
        case .signedOut:
            return "登录后连接"
        case .signedIn:
            return vpnManager.actionTitle
        }
    }

    private var connectionSubtitle: String {
        if let address = vpnManager.configuredServerAddress {
            return address
        }
        switch authenticationPhase {
        case .restoring:
            return "正在检查已有账号…"
        case .signedOut:
            return "无需先注册，连接时再关联账号"
        case .signedIn:
            return "选择节点后即可配置"
        }
    }

    private var statusColor: Color {
        switch vpnManager.status {
        case .connected:
            return .green
        case .connecting, .reasserting, .disconnecting:
            return .orange
        default:
            return .indigo
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private func formatDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: value)
            ?? ISO8601DateFormatter.withFractionalSeconds.date(from: value)
        guard let date else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct NodePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var nodeStore: NodeStore

    var body: some View {
        List(nodeStore.nodes) { node in
            Button {
                nodeStore.select(node.id)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(node.name)
                            .foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            Text(node.region)
                            Text(node.normalizedProtocol.uppercased())
                            Text("×\(node.rate.formatted(.number.precision(.fractionLength(0...1))))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let issue = node.configurationIssue {
                            Text(issue)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }

                    Spacer()
                    if nodeStore.selectedNode?.id == node.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.indigo)
                    }
                }
            }
            .disabled(node.configurationIssue != nil)
        }
        .navigationTitle("选择节点")
        .overlay {
            if nodeStore.nodes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无节点")
                        .font(.headline)
                    Text("请确认订阅有效后刷新。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18)
            )
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter
    }()
}
