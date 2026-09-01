import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

enum APIClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationRequired(String)
    case server(statusCode: Int, code: String?, message: String)
    case transport(String)
    case decoding(String)

    var isAuthenticationFailure: Bool {
        switch self {
        case .authenticationRequired:
            return true
        case let .server(statusCode, _, _):
            return statusCode == 401
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请求地址无效"
        case .invalidResponse:
            return "服务器返回了无效响应"
        case let .authenticationRequired(message):
            return message
        case let .server(_, _, message):
            return message
        case let .transport(message):
            return "网络连接失败：\(message)"
        case let .decoding(message):
            return "无法解析服务器响应：\(message)"
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void

    init<Value: Encodable>(_ value: Value) {
        encodeValue = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeValue(encoder)
    }
}

private struct APIEnvelope<Value: Decodable>: Decodable {
    let success: Bool
    let data: Value
    let message: String?
}

/// A single authenticated HTTP client for the app.
///
/// The actor owns refresh state, so simultaneous 401 responses reuse the same
/// refresh operation instead of rotating credentials in parallel.
actor APIClient {
    private struct RefreshOperation {
        let id: UUID
        let credentialGeneration: UInt64
        let task: Task<AuthTokens, Error>
    }

    let baseURL: URL
    private let session: URLSession
    private let credentialStore: any CredentialStoring
    private var refreshOperation: RefreshOperation?
    private var credentialMutationGeneration: UInt64 = 0
    private var credentialMutationInProgress = false

    init(
        baseURL: URL,
        session: URLSession? = nil,
        credentialStore: any CredentialStoring = KeychainCredentialStore()
    ) {
        self.baseURL = baseURL
        self.session = session ?? Self.makeSecureSession()
        self.credentialStore = credentialStore
    }

    func send<Response: Decodable>(
        _ method: HTTPMethod,
        path: String,
        body: (any Encodable)? = nil,
        requiresAuthorization: Bool = true,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        let encodedBody: Data?
        if let body {
            encodedBody = try JSONEncoder().encode(AnyEncodable(body))
        } else {
            encodedBody = nil
        }

        return try await perform(
            method,
            path: path,
            body: encodedBody,
            requiresAuthorization: requiresAuthorization,
            retryAfterRefresh: requiresAuthorization,
            as: responseType
        )
    }

    func adopt(_ tokens: AuthTokens) async throws {
        let mutation = beginCredentialMutation()
        defer {
            finishCredentialMutation(mutation.generation)
        }
        if let refreshTask = mutation.refreshTask {
            _ = try? await refreshTask.value
        }
        try Task.checkCancellation()
        guard mutation.generation == credentialMutationGeneration else {
            throw CancellationError()
        }
        try await credentialStore.save(tokens)
        guard mutation.generation == credentialMutationGeneration else {
            throw CancellationError()
        }
    }

    func hasStoredCredentials() async throws -> Bool {
        try await credentialStore.load() != nil
    }

    func clearCredentials() async throws {
        let mutation = beginCredentialMutation()
        defer {
            finishCredentialMutation(mutation.generation)
        }
        if let refreshTask = mutation.refreshTask {
            _ = try? await refreshTask.value
        }
        try Task.checkCancellation()
        guard mutation.generation == credentialMutationGeneration else {
            throw CancellationError()
        }
        try await credentialStore.clear()
        guard mutation.generation == credentialMutationGeneration else {
            throw CancellationError()
        }
    }

    /// A cancelled refresh may already be between its cancellation check and
    /// the Keychain write. Credential mutations establish a barrier before
    /// awaiting that task. This prevents another in-flight 401 from starting a
    /// second refresh while login or logout is replacing authentication state.
    private func beginCredentialMutation() -> (
        generation: UInt64,
        refreshTask: Task<AuthTokens, Error>?
    ) {
        credentialMutationGeneration &+= 1
        credentialMutationInProgress = true
        let operation = refreshOperation
        refreshOperation = nil
        operation?.task.cancel()
        return (credentialMutationGeneration, operation?.task)
    }

    private func finishCredentialMutation(_ generation: UInt64) {
        guard generation == credentialMutationGeneration else {
            return
        }
        credentialMutationInProgress = false
    }

    private func perform<Response: Decodable>(
        _ method: HTTPMethod,
        path: String,
        body: Data?,
        requiresAuthorization: Bool,
        retryAfterRefresh: Bool,
        as responseType: Response.Type
    ) async throws -> Response {
        var request = try makeRequest(method, path: path, body: body)
        var accessTokenUsed: String?

        if requiresAuthorization {
            guard let credentials = try await credentialStore.load() else {
                throw APIClientError.authenticationRequired("登录状态已失效，请重新登录")
            }
            accessTokenUsed = credentials.accessToken
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let httpResponse: HTTPURLResponse
        do {
            let result = try await session.data(for: request)
            guard let response = result.1 as? HTTPURLResponse else {
                throw APIClientError.invalidResponse
            }
            data = result.0
            httpResponse = response
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.transport(error.localizedDescription)
        }

        if httpResponse.statusCode == 401, retryAfterRefresh {
            do {
                let latestCredentials = try await credentialStore.load()
                guard let latestCredentials else {
                    throw APIClientError.authenticationRequired("登录状态已失效，请重新登录")
                }

                // A different request may already have completed a refresh
                // while this request's stale 401 was still in flight.
                if latestCredentials.accessToken == accessTokenUsed {
                    _ = try await refreshCredentials()
                }
            } catch {
                if (error as? APIClientError)?.isAuthenticationFailure == true {
                    try? await clearCredentials()
                }
                throw error
            }

            return try await perform(
                method,
                path: path,
                body: body,
                requiresAuthorization: true,
                retryAfterRefresh: false,
                as: responseType
            )
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw makeServerError(statusCode: httpResponse.statusCode, data: data)
        }

        return try decode(responseType, from: data, statusCode: httpResponse.statusCode)
    }

    private func refreshCredentials() async throws -> AuthTokens {
        guard !credentialMutationInProgress else {
            throw CancellationError()
        }
        let credentialGeneration = credentialMutationGeneration
        if let refreshOperation {
            guard refreshOperation.credentialGeneration
                    == credentialGeneration else {
                throw CancellationError()
            }
            return try await refreshOperation.task.value
        }

        guard let credentials = try await credentialStore.load() else {
            throw APIClientError.authenticationRequired("登录状态已失效，请重新登录")
        }
        guard !credentialMutationInProgress,
              credentialGeneration == credentialMutationGeneration else {
            throw CancellationError()
        }

        let operationID = UUID()
        let baseURL = baseURL
        let session = session
        let refreshToken = credentials.refreshToken

        let task = Task<AuthTokens, Error> { [self] in
            let url = try Self.makeURL(baseURL: baseURL, path: "auth/refresh")
            var request = URLRequest(url: url)
            request.httpMethod = HTTPMethod.post.rawValue
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RefreshTokenRequest(refreshToken: refreshToken))

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw APIClientError.transport(error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIClientError.invalidResponse
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                throw Self.makeServerError(statusCode: httpResponse.statusCode, data: data)
            }

            let tokens: AuthTokens
            do {
                tokens = try JSONDecoder().decode(AuthTokens.self, from: data)
            } catch {
                throw APIClientError.decoding(error.localizedDescription)
            }

            try Task.checkCancellation()
            try await commitRefreshedTokens(
                tokens,
                operationID: operationID,
                credentialGeneration: credentialGeneration
            )
            return tokens
        }

        refreshOperation = RefreshOperation(
            id: operationID,
            credentialGeneration: credentialGeneration,
            task: task
        )
        defer {
            if refreshOperation?.id == operationID {
                refreshOperation = nil
            }
        }
        return try await task.value
    }

    private func commitRefreshedTokens(
        _ tokens: AuthTokens,
        operationID: UUID,
        credentialGeneration: UInt64
    ) async throws {
        try Task.checkCancellation()
        guard !credentialMutationInProgress,
              credentialGeneration == credentialMutationGeneration,
              refreshOperation?.id == operationID else {
            throw CancellationError()
        }

        try await credentialStore.save(tokens)

        // A login/logout may have begun while the Keychain actor was writing.
        // It waits for this task before applying its newer mutation, so this
        // check turns the refresh into a failed stale operation and lets the
        // credential mutation deterministically win.
        try Task.checkCancellation()
        guard !credentialMutationInProgress,
              credentialGeneration == credentialMutationGeneration,
              refreshOperation?.id == operationID else {
            throw CancellationError()
        }
    }

    private func makeRequest(
        _ method: HTTPMethod,
        path: String,
        body: Data?
    ) throws -> URLRequest {
        let url = try Self.makeURL(baseURL: baseURL, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-Hans", forHTTPHeaderField: "Accept-Language")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private static func makeSecureSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    private static func makeURL(baseURL: URL, path: String) throws -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseHasAPIPrefix = baseURL.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .last == "api"

        guard !cleanPath.isEmpty else {
            throw APIClientError.invalidURL
        }

        var url = baseURL
        if !baseHasAPIPrefix {
            url.appendPathComponent("api")
        }
        cleanPath.split(separator: "/").forEach {
            url.appendPathComponent(String($0))
        }
        return url
    }

    private func decode<Response: Decodable>(
        _ responseType: Response.Type,
        from data: Data,
        statusCode: Int
    ) throws -> Response {
        do {
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["success"] != nil {
                if object["success"] as? Bool == false {
                    throw Self.makeServerError(statusCode: statusCode, data: data)
                }
                if object["data"] != nil {
                    return try JSONDecoder().decode(APIEnvelope<Response>.self, from: data).data
                }
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.decoding(error.localizedDescription)
        }
    }

    private func makeServerError(statusCode: Int, data: Data) -> APIClientError {
        Self.makeServerError(statusCode: statusCode, data: data)
    }

    private static func makeServerError(statusCode: Int, data: Data) -> APIClientError {
        var message = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        var code: String?

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let stringMessage = object["message"] as? String, !stringMessage.isEmpty {
                message = stringMessage
            } else if let messages = object["message"] as? [String], !messages.isEmpty {
                message = messages.joined(separator: "\n")
            }
            code = object["code"] as? String
        }

        if statusCode == 401 {
            return .authenticationRequired(message)
        }
        return .server(statusCode: statusCode, code: code, message: message)
    }
}
