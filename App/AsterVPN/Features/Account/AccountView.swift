import SwiftUI

struct AccountView: View {
    @ObservedObject var session: AuthSession
    @State private var showsDeleteAccount = false

    var body: some View {
        Form {
            Section("账号") {
                LabeledContent("邮箱", value: session.profile?.email ?? session.currentUser?.email ?? "—")
                LabeledContent(
                    "用户名",
                    value: session.profile?.username ?? session.currentUser?.username ?? "未设置"
                )
                if session.profile?.emailVerified == true {
                    LabeledContent("邮箱状态", value: "已验证")
                }
            }

            if let error = session.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("退出登录") {
                    Task {
                        await session.logout()
                    }
                }
                .disabled(session.isBusy)
            }

            Section("数据与法律") {
                NavigationLink {
                    PrivacyDisclosureView(requiresAcknowledgement: false)
                } label: {
                    Label("数据与隐私说明", systemImage: "hand.raised")
                }

                Link(
                    destination: AppConfiguration.current.privacyPolicyURL
                ) {
                    Label("完整隐私政策", systemImage: "safari")
                }

                Link(
                    destination: AppConfiguration.current.termsOfServiceURL
                ) {
                    Label("服务条款", systemImage: "doc.text")
                }

                Link(
                    destination: URL(
                        string: "https://apps.apple.com/account/subscriptions"
                    )!
                ) {
                    Label("管理 Apple 订阅", systemImage: "arrow.triangle.2.circlepath")
                }

                Link(destination: AppConfiguration.current.supportURL) {
                    Label("帮助与支持", systemImage: "questionmark.circle")
                }
            }

            Section {
                Button("永久删除账号", role: .destructive) {
                    session.clearMessages()
                    showsDeleteAccount = true
                }
                .disabled(session.isBusy)
            } footer: {
                Text("删除后账号不可恢复。删除账号不会自动取消 Apple App Store 订阅，请同时在系统“订阅”中确认状态。")
            }
        }
        .navigationTitle("账号")
        .task {
            if session.profile == nil {
                await session.refreshProfile()
            }
        }
        .sheet(isPresented: $showsDeleteAccount) {
            DeleteAccountView(session: session)
        }
    }
}

private struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: AuthSession
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("此操作会停用账号、删除可删除的个人数据并取消未支付订单，且无法撤销。")
                        .foregroundStyle(.red)
                }

                Section("确认身份") {
                    SecureField("当前密码", text: $password)
                        .textContentType(.password)
                    TextField("输入 DELETE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }

                Section {
                    Button("永久删除账号", role: .destructive) {
                        Task {
                            if await session.deleteAccount(
                                password: password,
                                confirmation: confirmation
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        session.isBusy
                            || password.count < 8
                            || confirmation != "DELETE"
                    )
                }
            }
            .navigationTitle("删除账号")
            .interactiveDismissDisabled(session.isBusy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(session.isBusy)
                }
            }
        }
    }
}
