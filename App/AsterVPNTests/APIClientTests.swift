import Foundation
import XCTest
@testable import AsterVPN

final class APIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testAuthenticatedRequestRefreshesAndRetriesAfterUnauthorizedResponse() async throws {
        let store = InMemoryCredentialStore(
            credentials: AuthTokens(accessToken: "expired-access", refreshToken: "refresh-token")
        )
        let session = makeSession()
        let lock = NSLock()
        var refreshRequests = 0

        URLProtocolStub.handler = { request in
            switch request.url?.path {
            case "/api/auth/refresh":
                lock.lock()
                refreshRequests += 1
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.1)
                return Self.response(
                    request,
                    statusCode: 200,
                    json: """
                    {"accessToken":"fresh-access","refreshToken":"fresh-refresh"}
                    """
                )
            case "/api/user/profile":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-access" {
                    return Self.response(
                        request,
                        statusCode: 200,
                        json: """
                        {
                          "id":"user-1",
                          "email":"person@example.com",
                          "username":"person",
                          "emailVerified":true,
                          "isActive":true,
                          "isAdmin":false
                        }
                        """
                    )
                }
                return Self.response(
                    request,
                    statusCode: 401,
                    json: """
                    {"success":false,"code":"HTTP_401","message":"令牌无效"}
                    """
                )
            default:
                XCTFail("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
                return Self.response(request, statusCode: 404, json: "{}")
            }
        }

        let client = APIClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: session,
            credentialStore: store
        )
        async let firstProfile: UserProfile = client.send(.get, path: "user/profile")
        async let secondProfile: UserProfile = client.send(.get, path: "user/profile")
        let profiles = try await [firstProfile, secondProfile]

        XCTAssertEqual(profiles.map(\.email), ["person@example.com", "person@example.com"])
        XCTAssertEqual(refreshRequests, 1)
        let stored = await store.load()
        XCTAssertEqual(stored?.accessToken, "fresh-access")
        XCTAssertEqual(stored?.refreshToken, "fresh-refresh")
    }

    func testDecodesWrappedAccountDeletionResult() async throws {
        let store = InMemoryCredentialStore(
            credentials: AuthTokens(accessToken: "access", refreshToken: "refresh")
        )
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/user/account")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            let body = try XCTUnwrap(request.httpBody)
            let payload = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(payload["password"], "password123")
            XCTAssertEqual(payload["confirmation"], "DELETE")
            return Self.response(
                request,
                statusCode: 200,
                json: """
                {
                  "success":true,
                  "data":{
                    "deletedAt":"2026-07-23T00:00:00.000Z",
                    "cancelledPendingOrders":2,
                    "retainedData":["订单与支付记录"],
                    "appStoreSubscriptionAction":"请检查系统订阅"
                  },
                  "message":"账号已永久删除"
                }
                """
            )
        }

        let client = APIClient(
            baseURL: URL(string: "https://api.example.com/api")!,
            session: makeSession(),
            credentialStore: store
        )
        let result = try await AccountAPI(client: client).deleteAccount(
            password: "password123",
            confirmation: "DELETE"
        )

        XCTAssertEqual(result.cancelledPendingOrders, 2)
        XCTAssertEqual(result.appStoreSubscriptionAction, "请检查系统订阅")
    }

    func testSurfacesBackendValidationMessage() async throws {
        URLProtocolStub.handler = { request in
            Self.response(
                request,
                statusCode: 400,
                json: """
                {
                  "success":false,
                  "code":"HTTP_400",
                  "message":["请输入有效的邮箱地址","密码不能为空"]
                }
                """
            )
        }

        let client = APIClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: makeSession(),
            credentialStore: InMemoryCredentialStore()
        )

        do {
            let _: AuthenticationResponse = try await AuthenticationAPI(client: client).login(
                email: "invalid",
                password: ""
            )
            XCTFail("Expected request to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "请输入有效的邮箱地址\n密码不能为空"
            )
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int,
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("URLProtocolStub handler was not configured")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
