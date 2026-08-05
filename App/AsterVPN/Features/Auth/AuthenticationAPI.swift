import Foundation

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegistrationRequest: Encodable {
    let email: String
    let password: String
    let verifyCode: String
    let inviteCode: String?
}

struct SendVerificationCodeRequest: Encodable {
    let email: String
    let type: VerificationCodePurpose
}

struct ResetPasswordRequest: Encodable {
    let email: String
    let verifyCode: String
    let newPassword: String
}

struct AuthenticationAPI {
    let client: APIClient

    func login(email: String, password: String) async throws -> AuthenticatedUser {
        let response: AuthenticationResponse = try await client.send(
            .post,
            path: "auth/login",
            body: LoginRequest(email: email, password: password),
            requiresAuthorization: false
        )
        try await client.adopt(response.tokens)
        return response.user
    }

    func register(
        email: String,
        password: String,
        verificationCode: String,
        inviteCode: String?
    ) async throws -> AuthenticatedUser {
        let response: AuthenticationResponse = try await client.send(
            .post,
            path: "auth/register",
            body: RegistrationRequest(
                email: email,
                password: password,
                verifyCode: verificationCode,
                inviteCode: inviteCode?.nilIfEmpty?.uppercased()
            ),
            requiresAuthorization: false
        )
        try await client.adopt(response.tokens)
        return response.user
    }

    @discardableResult
    func sendVerificationCode(
        email: String,
        purpose: VerificationCodePurpose
    ) async throws -> String {
        let response: MessageResponse = try await client.send(
            .post,
            path: "auth/send-code",
            body: SendVerificationCodeRequest(email: email, type: purpose),
            requiresAuthorization: false
        )
        return response.message
    }

    @discardableResult
    func resetPassword(
        email: String,
        verificationCode: String,
        newPassword: String
    ) async throws -> String {
        let response: MessageResponse = try await client.send(
            .post,
            path: "auth/reset-password",
            body: ResetPasswordRequest(
                email: email,
                verifyCode: verificationCode,
                newPassword: newPassword
            ),
            requiresAuthorization: false
        )
        return response.message
    }

    func logout() async throws {
        try await client.clearCredentials()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
