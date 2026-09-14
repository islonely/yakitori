import Foundation

public struct APIError: LocalizedError, Equatable, Sendable {
    public var statusCode: Int?
    public var code: String?
    public var message: String

    public init(statusCode: Int? = nil, code: String? = nil, message: String) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    public var isNetworkFailure: Bool { statusCode == nil }
}

/// Thin JSON client for the platform's `/v1` API.
public final class APIClient: @unchecked Sendable {
    private let configuration: PlatformConfiguration
    private let transport: HTTPTransport
    private let lock = NSLock()
    private var _authToken: String?

    public init(configuration: PlatformConfiguration, transport: HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public var authToken: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _authToken
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _authToken = newValue
        }
    }

    private func makeRequest(
        method: String,
        path: String,
        body: [String: Any]?
    ) throws -> HTTPRequest {
        guard let url = URL(string: path, relativeTo: configuration.apiBaseURL)?
            .absoluteURL
        else {
            throw APIError(message: "Invalid request URL.")
        }

        var headers: [String: String] = ["Accept": "application/json"]
        var data: Data?
        if let body {
            headers["Content-Type"] = "application/json"
            data = try JSONSerialization.data(withJSONObject: body)
        }
        if let token = authToken {
            headers["Authorization"] = "Bearer \(token)"
        }

        return HTTPRequest(method: method, url: url, headers: headers, body: data)
    }

    @discardableResult
    public func perform(
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async throws -> Data {
        let request = try makeRequest(method: method, path: path, body: body)

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw APIError(message: error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.decodeError(response)
        }
        return response.data
    }

    public func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await perform(method: "GET", path: path)
        return try decode(data)
    }

    public func post<T: Decodable>(
        _ path: String,
        json: [String: Any]?,
        as type: T.Type
    ) async throws -> T {
        let data = try await perform(method: "POST", path: path, body: json)
        return try decode(data)
    }

    public func delete<T: Decodable>(
        _ path: String,
        as type: T.Type
    ) async throws -> T {
        let data = try await perform(method: "DELETE", path: path)
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        guard !data.isEmpty else {
            throw APIError(message: "The server returned an empty response.")
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "Unexpected response from the server.")
        }
    }

    private static func decodeError(_ response: HTTPResponse) -> APIError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                let code: String?
                let message: String?
            }
            let error: Body
        }

        if let envelope = try? decoder.decode(Envelope.self, from: response.data) {
            return APIError(
                statusCode: response.statusCode,
                code: envelope.error.code,
                message: envelope.error.message ?? "Request failed."
            )
        }
        return APIError(
            statusCode: response.statusCode,
            message: "Request failed (\(response.statusCode))."
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
