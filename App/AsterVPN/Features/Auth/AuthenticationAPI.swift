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

struct CreateGuestRequest: Encodable {
    let installationId: String
}

struct AuthenticationAPI {
    let client: APIClient

    func createGuest(installationID: UUID) async throws -> AuthenticationResponse {
        let response: AuthenticationResponse = try await client.send(
            .post,
            path: "auth/guest",
            body: CreateGuestRequest(installationId: installationID.uuidString),
            requiresAuthorization: false
        )
        try await client.adopt(response.tokens)
        return response
    }

    func login(
        email: String,
        password: String,
        claimingGuest: Bool = false
    ) async throws -> AuthenticationResponse {
        let response: AuthenticationResponse = try await client.send(
            .post,
            path: claimingGuest ? "auth/guest/login" : "auth/login",
            body: LoginRequest(email: email, password: password),
            requiresAuthorization: claimingGuest
        )
        try await client.adopt(response.tokens)
        return response
    }

    func register(
        email: String,
        password: String,
        verificationCode: String,
        inviteCode: String?,
        claimingGuest: Bool = false
    ) async throws -> AuthenticationResponse {
        let response: AuthenticationResponse = try await client.send(
            .post,
            path: claimingGuest ? "auth/guest/register" : "auth/register",
            body: RegistrationRequest(
                email: email,
                password: password,
                verifyCode: verificationCode,
                inviteCode: inviteCode?.nilIfEmpty?.uppercased()
            ),
            requiresAuthorization: claimingGuest
        )
        try await client.adopt(response.tokens)
        return response
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
