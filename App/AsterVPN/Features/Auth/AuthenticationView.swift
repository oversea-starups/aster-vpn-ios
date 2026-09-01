import SwiftUI

struct AuthenticationView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"

        var id: Self { self }
    }

    @ObservedObject var session: AuthSession
    let allowsDismissal: Bool
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var inviteCode = ""
    @State private var acceptedTerms = false
    @State private var showsPasswordReset = false

    init(session: AuthSession, allowsDismissal: Bool = false) {
        self.session = session
        self.allowsDismissal = allowsDismissal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("认证方式", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("密码（8–64 位）", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)

                    if mode == .register {
                        HStack {
                            TextField("邮箱验证码", text: $verificationCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button("发送") {
                                Task {
                                    await session.sendVerificationCode(
                                        email: email,
                                        purpose: .register
                                    )
                                }
                            }
                            .disabled(session.isBusy)
                        }

                        TextField("邀请码（可选）", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        Toggle(isOn: $acceptedTerms) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("我同意服务条款和隐私政策")
                                HStack(spacing: 12) {
                                    Link(
                                        "服务条款",
                                        destination: AppConfiguration.current.termsOfServiceURL
                                    )
                                    Link(
                                        "隐私政策",
                                        destination: AppConfiguration.current.privacyPolicyURL
                                    )
                                }
                                .font(.caption)
                            }
                        }
                    }
                }

                if let error = session.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityLabel("错误：\(error)")
                    }
                }

                if let notice = session.noticeMessage {
                    Section {
                        Text(notice)
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if session.isBusy {
                                ProgressView()
                            } else {
                                Text(mode.rawValue)
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        session.isBusy
                            || (mode == .register && !acceptedTerms)
                    )

                    if mode == .login {
                        Button("忘记密码？") {
                            session.clearMessages()
                            showsPasswordReset = true
                        }
                    }
                }
            }
            .navigationTitle("Aster VPN")
            .toolbar {
                if allowsDismissal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("稍后") {
                            session.clearMessages()
                            dismiss()
                        }
                        .disabled(session.isBusy)
                    }
                }
            }
            .onChange(of: mode) { _ in
                session.clearMessages()
                password = ""
            }
            .sheet(isPresented: $showsPasswordReset) {
                PasswordResetView(session: session, initialEmail: email)
            }
        }
    }

    private func submit() {
        Task {
            switch mode {
            case .login:
                await session.login(email: email, password: password)
            case .register:
                guard acceptedTerms else {
                    session.errorMessage = "请先同意服务条款和隐私政策"
                    return
                }
                await session.register(
                    email: email,
                    password: password,
                    verificationCode: verificationCode,
                    inviteCode: inviteCode
                )
            }
        }
    }
}

private struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: AuthSession
    @State private var email: String
    @State private var verificationCode = ""
    @State private var newPassword = ""
    @State private var confirmation = ""

    init(session: AuthSession, initialEmail: String) {
        self.session = session
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("验证邮箱") {
                    TextField("邮箱", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        TextField("验证码", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("发送") {
                            Task {
                                await session.sendVerificationCode(
                                    email: email,
                                    purpose: .resetPassword
                                )
                            }
                        }
                        .disabled(session.isBusy)
                    }
                }

                Section("设置新密码") {
                    SecureField("新密码（8–64 位）", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("再次输入新密码", text: $confirmation)
                        .textContentType(.newPassword)
                }

                if let error = session.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
                if let notice = session.noticeMessage {
                    Text(notice)
                        .foregroundStyle(.green)
                }

                Button {
                    guard newPassword == confirmation else {
                        session.errorMessage = "两次输入的密码不一致"
                        return
                    }
                    Task {
                        if await session.resetPassword(
                            email: email,
                            verificationCode: verificationCode,
                            newPassword: newPassword
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if session.isBusy {
                            ProgressView()
                        } else {
                            Text("重置密码")
                        }
                        Spacer()
                    }
                }
                .disabled(session.isBusy)
            }
            .navigationTitle("重置密码")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
