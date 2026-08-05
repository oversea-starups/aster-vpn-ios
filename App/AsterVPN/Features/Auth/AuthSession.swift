import Combine
import Foundation

@MainActor
final class AuthSession: ObservableObject {
    private struct SessionInvalidationOperation {
        let id: UUID
        let task: Task<Void, Error>
    }

    enum Phase: Equatable {
        case restoring
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .restoring
    @Published private(set) var currentUser: AuthenticatedUser?
    @Published private(set) var profile: UserProfile?
    @Published private(set) var sessionGeneration = UUID()
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let client: APIClient
    private let authenticationAPI: AuthenticationAPI
    private let accountAPI: AccountAPI
    private let sessionInvalidationHandler: @MainActor () -> Void
    private let sessionTerminationHandler: @MainActor () async throws -> Void
    private let defaults: UserDefaults
    private let cleanupPendingKey: String
    private var invalidationOperation: SessionInvalidationOperation?
    private var busyOperationID: UUID?

    init(
        client: APIClient,
        sessionInvalidationHandler: @escaping @MainActor () -> Void = {},
        sessionTerminationHandler: @escaping @MainActor () async throws -> Void = {},
        defaults: UserDefaults = .standard,
        cleanupPendingKey: String = "aster-session-cleanup-pending"
    ) {
        self.client = client
        authenticationAPI = AuthenticationAPI(client: client)
        accountAPI = AccountAPI(client: client)
        self.sessionInvalidationHandler = sessionInvalidationHandler
        self.sessionTerminationHandler = sessionTerminationHandler
        self.defaults = defaults
        self.cleanupPendingKey = cleanupPendingKey
    }

    convenience init(
        configuration: AppConfiguration = .current,
        session: URLSession? = nil,
        credentialStore: any CredentialStoring = KeychainCredentialStore()
    ) {
        self.init(
            client: APIClient(
                baseURL: configuration.apiBaseURL,
                session: session,
                credentialStore: credentialStore
            ),
            sessionInvalidationHandler: {},
            sessionTerminationHandler: {},
            defaults: .standard
        )
    }

    func restore() async {
        guard phase == .restoring else {
            return
        }
        if defaults.bool(forKey: cleanupPendingKey) {
            try? await terminateSession()
            return
        }

        do {
            guard try await client.hasStoredCredentials() else {
                try? await terminateSession()
                return
            }

            do {
                let profile = try await accountAPI.profile()
                apply(profile)
                phase = .signedIn
            } catch {
                // Without a server-confirmed user identity the app cannot bind
                // StoreKit or tunnel credentials to an owner. Fail closed and
                // require a fresh login instead of entering a nil-owner
                // "offline signed-in" state.
                try? await terminateSession(presenting: error)
            }
        } catch {
            try? await terminateSession(presenting: error)
        }
    }

    @discardableResult
    func login(email: String, password: String) async -> Bool {
        guard validateEmail(email) else {
            errorMessage = "请输入有效的邮箱地址"
            return false
        }
        return await runAuthentication {
            try await authenticationAPI.login(
                email: normalize(email),
                password: password
            )
        }
    }

    @discardableResult
    func register(
        email: String,
        password: String,
        verificationCode: String,
        inviteCode: String?
    ) async -> Bool {
        guard validateEmail(email) else {
            errorMessage = "请输入有效的邮箱地址"
            return false
        }
        guard validatePassword(password) else {
            errorMessage = "密码长度必须为 8 到 64 位"
            return false
        }
        guard (4...8).contains(verificationCode.count) else {
            errorMessage = "请输入 4 到 8 位验证码"
            return false
        }

        return await runAuthentication {
            try await authenticationAPI.register(
                email: normalize(email),
                password: password,
                verificationCode: verificationCode,
                inviteCode: inviteCode
            )
        }
    }

    @discardableResult
    func sendVerificationCode(
        email: String,
        purpose: VerificationCodePurpose
    ) async -> Bool {
        guard validateEmail(email) else {
            errorMessage = "请输入有效的邮箱地址"
            return false
        }

        return await runBusy { operationID in
            let message = try await authenticationAPI.sendVerificationCode(
                email: normalize(email),
                purpose: purpose
            )
            guard busyOperationID == operationID else {
                throw CancellationError()
            }
            noticeMessage = message
        }
    }

    @discardableResult
    func resetPassword(
        email: String,
        verificationCode: String,
        newPassword: String
    ) async -> Bool {
        guard validateEmail(email) else {
            errorMessage = "请输入有效的邮箱地址"
            return false
        }
        guard !verificationCode.isEmpty else {
            errorMessage = "请输入验证码"
            return false
        }
        guard validatePassword(newPassword) else {
            errorMessage = "密码长度必须为 8 到 64 位"
            return false
        }

        return await runBusy { operationID in
            let message = try await authenticationAPI.resetPassword(
                email: normalize(email),
                verificationCode: verificationCode,
                newPassword: newPassword
            )
            guard busyOperationID == operationID else {
                throw CancellationError()
            }
            noticeMessage = message
        }
    }

    func refreshProfile() async {
        guard phase == .signedIn,
              let operationID = beginBusyOperation() else {
            return
        }
        let generation = sessionGeneration
        clearMessages()

        do {
            let profile = try await accountAPI.profile()
            guard isCurrentSession(generation) else {
                finishBusyOperation(operationID)
                return
            }
            apply(profile)
        } catch {
            guard isCurrentSession(generation) else {
                finishBusyOperation(operationID)
                return
            }
            if isAuthenticationFailure(error) {
                try? await terminateSession(presenting: error)
            } else {
                present(error)
            }
        }
        finishBusyOperation(operationID)
    }

    @discardableResult
    func deleteAccount(password: String, confirmation: String) async -> Bool {
        guard validatePassword(password) else {
            errorMessage = "密码长度必须为 8 到 64 位"
            return false
        }
        guard confirmation == "DELETE" else {
            errorMessage = "请输入 DELETE 确认永久删除"
            return false
        }

        guard phase == .signedIn,
              let operationID = beginBusyOperation() else {
            return false
        }
        let generation = sessionGeneration
        clearMessages()
        do {
            let result = try await accountAPI.deleteAccount(
                password: password,
                confirmation: confirmation
            )
            guard isCurrentSession(generation) else {
                finishBusyOperation(operationID)
                return false
            }

            do {
                try await terminateSession()
            } catch {
                errorMessage = "账号已删除，但本地会话清理失败：\(error.localizedDescription)"
            }

            noticeMessage = result.appStoreSubscriptionAction
            finishBusyOperation(operationID)
            return true
        } catch {
            if isCurrentSession(generation) {
                handleAuthenticatedRequestError(error)
            }
            finishBusyOperation(operationID)
            return false
        }
    }

    @discardableResult
    func logout() async -> Bool {
        guard beginBusyOperation() != nil else {
            return false
        }
        clearMessages()
        do {
            try await terminateSession()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func clearMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    func handleProtectedRequestError(_ error: Error) {
        handleAuthenticatedRequestError(error)
    }

    private func runAuthentication(
        operation: () async throws -> AuthenticatedUser
    ) async -> Bool {
        guard phase == .signedOut else {
            return false
        }
        if defaults.bool(forKey: cleanupPendingKey) {
            do {
                try await terminateSession()
            } catch {
                return false
            }
        }
        guard let operationID = beginBusyOperation() else {
            return false
        }
        clearMessages()
        do {
            let user = try await operation()
            guard busyOperationID == operationID else {
                return false
            }
            let generation = UUID()
            sessionGeneration = generation
            currentUser = user
            phase = .signedIn

            // Authentication has succeeded even if this optional hydration
            // request is temporarily unavailable.
            do {
                let profile = try await accountAPI.profile()
                guard isCurrentSession(generation) else {
                    finishBusyOperation(operationID)
                    return false
                }
                apply(profile)
            } catch where !isAuthenticationFailure(error) {
                if isCurrentSession(generation) {
                    present(error)
                }
            } catch {
                if isCurrentSession(generation) {
                    try? await terminateSession(presenting: error)
                }
                finishBusyOperation(operationID)
                return false
            }

            guard isCurrentSession(generation) else {
                finishBusyOperation(operationID)
                return false
            }
            finishBusyOperation(operationID)
            return true
        } catch {
            guard busyOperationID == operationID else {
                return false
            }
            present(error)
            finishBusyOperation(operationID)
            return false
        }
    }

    private func runBusy(
        operation: (UUID) async throws -> Void
    ) async -> Bool {
        guard let operationID = beginBusyOperation() else {
            return false
        }
        clearMessages()
        do {
            try await operation(operationID)
            finishBusyOperation(operationID)
            return true
        } catch {
            guard busyOperationID == operationID else {
                return false
            }
            if isAuthenticationFailure(error) {
                try? await terminateSession(presenting: error)
            } else {
                present(error)
            }
            finishBusyOperation(operationID)
            return false
        }
    }

    private func apply(_ profile: UserProfile) {
        self.profile = profile
        currentUser = AuthenticatedUser(profile: profile)
    }

    private func clearAuthenticatedState() {
        currentUser = nil
        profile = nil
    }

    private func handleAuthenticatedRequestError(_ error: Error) {
        if isAuthenticationFailure(error) {
            guard phase == .signedIn else {
                return
            }
            let operation = startSessionInvalidation()
            Task { [weak self] in
                guard let self else { return }
                try? await self.awaitSessionInvalidation(
                    operation,
                    presenting: error
                )
            }
            return
        }
        present(error)
    }

    private func terminateSession(presenting error: Error? = nil) async throws {
        let operation = startSessionInvalidation()
        try await awaitSessionInvalidation(operation, presenting: error)
    }

    private func startSessionInvalidation() -> SessionInvalidationOperation {
        if let invalidationOperation {
            return invalidationOperation
        }

        beginSessionInvalidation()
        defaults.set(true, forKey: cleanupPendingKey)
        busyOperationID = nil
        isBusy = true

        let authenticationAPI = authenticationAPI
        let sessionTerminationHandler = sessionTerminationHandler
        let operationID = UUID()
        let task = Task { @MainActor in
            var failureMessages: [String] = []

            do {
                try await authenticationAPI.logout()
            } catch {
                failureMessages.append(
                    "登录凭据清理失败：\(Self.errorDescription(error))"
                )
            }

            do {
                try await sessionTerminationHandler()
            } catch {
                failureMessages.append(
                    "VPN 配置清理失败：\(Self.errorDescription(error))"
                )
            }

            if !failureMessages.isEmpty {
                throw SessionCleanupError(messages: failureMessages)
            }
        }
        let operation = SessionInvalidationOperation(
            id: operationID,
            task: task
        )
        invalidationOperation = operation
        return operation
    }

    private func awaitSessionInvalidation(
        _ operation: SessionInvalidationOperation,
        presenting triggeringError: Error?
    ) async throws {
        do {
            try await operation.task.value
            defaults.set(false, forKey: cleanupPendingKey)
            finishSessionInvalidation(operation)
            if let triggeringError {
                present(triggeringError)
            }
        } catch {
            finishSessionInvalidation(operation)
            let failure = SessionCleanupError(
                messages: [
                    triggeringError.map {
                        "会话失效：\(Self.errorDescription($0))"
                    },
                    "安全清理未完成：\(Self.errorDescription(error))",
                ].compactMap { $0 }
            )
            present(failure)
            throw failure
        }
    }

    private func beginSessionInvalidation() {
        sessionGeneration = UUID()
        sessionInvalidationHandler()
        clearAuthenticatedState()
        phase = .signedOut
    }

    private func finishSessionInvalidation(
        _ operation: SessionInvalidationOperation
    ) {
        guard invalidationOperation?.id == operation.id else {
            return
        }
        invalidationOperation = nil
        isBusy = false
    }

    private func beginBusyOperation() -> UUID? {
        guard !isBusy, invalidationOperation == nil else {
            return nil
        }
        let operationID = UUID()
        busyOperationID = operationID
        isBusy = true
        return operationID
    }

    private func finishBusyOperation(_ operationID: UUID) {
        guard busyOperationID == operationID else {
            return
        }
        busyOperationID = nil
        isBusy = false
    }

    private func isCurrentSession(_ generation: UUID) -> Bool {
        phase == .signedIn && sessionGeneration == generation
    }

    private static func errorDescription(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private func present(_ error: Error) {
        if error is CancellationError {
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private func isAuthenticationFailure(_ error: Error) -> Bool {
        (error as? APIClientError)?.isAuthenticationFailure == true
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validateEmail(_ email: String) -> Bool {
        let normalized = normalize(email)
        guard let at = normalized.firstIndex(of: "@"),
              at != normalized.startIndex,
              normalized.index(after: at) != normalized.endIndex,
              normalized[normalized.index(after: at)...].contains(".") else {
            return false
        }
        return true
    }

    private func validatePassword(_ password: String) -> Bool {
        (8...64).contains(password.count)
    }
}

private struct SessionCleanupError: LocalizedError {
    let messages: [String]

    var errorDescription: String? {
        messages.joined(separator: "\n")
    }
}
