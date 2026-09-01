import Foundation
import XCTest
@testable import Aster

final class NodeSubscriptionClientTests: XCTestCase {
    override func tearDown() {
        SubscriptionURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchAcceptsNonEmptyHTTP200PayloadWithinLimit() async throws {
        let expected = Data("vless://safe-location".utf8)
        SubscriptionURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Accept"),
                "text/plain, application/octet-stream;q=0.9"
            )
            return (Self.response(statusCode: 200), expected)
        }

        let received = try await makeClient().fetch(from: Self.publicURL)

        XCTAssertEqual(received, expected)
    }

    func testFetchRejectsNonSuccessAndEmptyResponses() async {
        SubscriptionURLProtocol.handler = { _ in
            (Self.response(statusCode: 503), Data("unavailable".utf8))
        }
        await assertInvalidResponse(from: makeClient())

        SubscriptionURLProtocol.handler = { _ in
            (Self.response(statusCode: 200), Data())
        }
        await assertInvalidResponse(from: makeClient())
    }

    func testFetchRejectsDeclaredContentLengthAboveHardLimit() async {
        let oversizedLength = NodeSubscriptionParser.maximumPayloadBytes + 1
        SubscriptionURLProtocol.handler = { _ in
            (
                Self.response(
                    statusCode: 200,
                    headers: ["Content-Length": String(oversizedLength)]
                ),
                Data("x".utf8)
            )
        }

        await assertInvalidResponse(from: makeClient())
    }

    func testFetchRejectsUnknownLengthBodyAboveHardLimit() async {
        let oversized = Data(
            repeating: 0x61,
            count: NodeSubscriptionParser.maximumPayloadBytes + 1
        )
        SubscriptionURLProtocol.handler = { _ in
            (Self.response(statusCode: 200), oversized)
        }

        await assertInvalidResponse(from: makeClient())
    }

    func testFetchRejectsUnsafeURLBeforeStartingRequest() async {
        var requestStarted = false
        SubscriptionURLProtocol.handler = { _ in
            requestStarted = true
            return (Self.response(statusCode: 200), Data("x".utf8))
        }

        do {
            _ = try await makeClient().fetch(from: URL(string: "https://127.0.0.1/catalog")!)
            XCTFail("Expected an unsafe URL to be rejected")
        } catch let error as NodeSubscriptionClientError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(requestStarted)
    }

    private func makeClient() -> URLSessionNodeSubscriptionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubscriptionURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSessionNodeSubscriptionClient(configuration: configuration)
    }

    private func assertInvalidResponse(
        from client: URLSessionNodeSubscriptionClient,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await client.fetch(from: Self.publicURL)
            XCTFail("Expected the response to be rejected", file: file, line: line)
        } catch let error as NodeSubscriptionClientError {
            XCTAssertEqual(error, .invalidResponse, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private static let publicURL = URL(string: "https://locations.astervpn.com/catalog")!

    private static func response(
        statusCode: Int,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: publicURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}

private final class SubscriptionURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
