import Foundation

private struct DeleteAccountRequest: Encodable {
    let password: String
    let confirmation: String
}

struct AccountAPI {
    let client: APIClient

    func profile() async throws -> UserProfile {
        try await client.send(.get, path: "user/profile")
    }

    func deleteAccount(password: String, confirmation: String) async throws -> AccountDeletionResult {
        try await client.send(
            .delete,
            path: "user/account",
            body: DeleteAccountRequest(password: password, confirmation: confirmation)
        )
    }
}
