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

    init(id: String, email: String, username: String?, isAdmin: Bool) {
        self.id = id
        self.email = email
        self.username = username
        self.isAdmin = isAdmin
    }

    init(profile: UserProfile) {
        id = profile.id
        email = profile.email
        username = profile.username
        isAdmin = profile.isAdmin
    }
}

struct AuthenticationResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthenticatedUser

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
