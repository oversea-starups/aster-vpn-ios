@preconcurrency import Foundation

protocol NodeSubscriptionFetching: Sendable {
    func fetch(from url: URL) async throws -> Data
}

final class URLSessionNodeSubscriptionClient: NSObject, NodeSubscriptionFetching, URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    private lazy var session: URLSession = {
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        self.configuration = configuration
        super.init()
    }

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
        super.init()
    }

    func fetch(from url: URL) async throws -> Data {
        guard AppConfiguration.validatedPublicHTTPSURL(url.absoluteString) != nil else {
            throw NodeSubscriptionClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/plain, application/octet-stream;q=0.9", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        guard
            let response = response as? HTTPURLResponse,
            response.statusCode == 200,
            response.expectedContentLength <= Int64(NodeSubscriptionParser.maximumPayloadBytes)
        else {
            throw NodeSubscriptionClientError.invalidResponse
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < NodeSubscriptionParser.maximumPayloadBytes else {
                throw NodeSubscriptionClientError.invalidResponse
            }
            data.append(byte)
        }
        guard !data.isEmpty else {
            throw NodeSubscriptionClientError.invalidResponse
        }
        return data
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard
            let originalHost = task.originalRequest?.url?.host?.lowercased(),
            let redirectedURL = request.url,
            redirectedURL.host?.lowercased() == originalHost,
            AppConfiguration.validatedPublicHTTPSURL(redirectedURL.absoluteString) != nil
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum NodeSubscriptionClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "VPN location updates aren't securely configured."
        case .invalidResponse:
            return "Aster couldn't download a verified location update."
        }
    }
}
