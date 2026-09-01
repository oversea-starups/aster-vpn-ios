import Foundation

struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let username: String?
    let isAdmin: Bool
    let isGuest: Bool

    init(
        id: String,
        email: String,
        username: String?,
        isAdmin: Bool,
        isGuest: Bool = false
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.isAdmin = isAdmin
        self.isGuest = isGuest
    }

    init(profile: UserProfile) {
        id = profile.id
        email = profile.email
        username = profile.username
        isAdmin = profile.isAdmin
        isGuest = profile.isGuest
    }
}

struct AuthenticationResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthenticatedUser
    let claimedAppAccountToken: String?

    var tokens: AuthTokens {
        AuthTokens(accessToken: accessToken, refreshToken: refreshToken)
    }
}

struct RefreshTokenRequest: Encodable, Sendable {
    let refreshToken: String
}

struct MessageResponse: Decodable, Equatable, Sendable {
    let message: String
}

enum VerificationCodePurpose: String, Encodable, Sendable {
    case register
    case resetPassword = "reset-password"
}
