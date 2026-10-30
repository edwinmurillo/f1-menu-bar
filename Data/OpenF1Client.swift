import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let retryAfter: String?
    public init(data: Data, status: Int, retryAfter: String? = nil) {
        self.data = data; self.status = status; self.retryAfter = retryAfter
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard response.expectedContentLength <= 6_000_000 else { throw APIError.responseTooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            guard data.count < 6_000_000 else { throw APIError.responseTooLarge }
            if data.count.isMultiple(of: 16_384) { try Task.checkCancellation() }
            data.append(byte)
        }
        return HTTPResponse(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
}

public enum APIError: LocalizedError, Equatable, Sendable {
    case invalidResponse, responseTooLarge, subscriptionRequired, invalidData(String)
    case http(Int), rateLimited(Date)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The data service returned an invalid response."
        case .responseTooLarge: "The response exceeded the app’s data limit."
        case .subscriptionRequired: "The data service temporarily requires authentication. Saved data will be kept and another source tried."
        case .invalidData(let detail): "The downloaded data could not be read: \(detail)"
        case .http(let code): "The data service is unavailable (HTTP \(code)). Try again later."
        case .rateLimited(let date): "The data service asked us to wait until \(date.formatted(date: .omitted, time: .shortened))."
        }
    }
}

actor RequestGate {
    private let spacing: Duration
    private var nextSlot = ContinuousClock.now
    init(spacing: Duration) { self.spacing = spacing }
    func wait() async throws {
        let slot = max(nextSlot, .now)
        nextSlot = slot.advanced(by: spacing)
        try await ContinuousClock().sleep(until: slot)
        try Task.checkCancellation()
    }
}

public actor OpenF1Client {
    private let http: JSONHTTPClient

    public init(transport: any HTTPTransport = URLSessionTransport(), requestSpacing: Duration = .milliseconds(2100)) {
        http = JSONHTTPClient(transport: transport, requestSpacing: requestSpacing)
    }

    func get<T: Decodable & Sendable>(_ endpoint: String, query: [URLQueryItem]) async throws -> [T] {
        var components = URLComponents(string: "https://api.openf1.org/v1/\(endpoint)")!
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidResponse }
        let data = try await http.get(url)
        do {
            let decoded = try JSONCoding.decoder().decode([T].self, from: data)
            guard decoded.count <= 15_000 else { throw APIError.responseTooLarge }
            return decoded
        } catch let error as APIError { throw error }
        catch { throw APIError.invalidData("unexpected OpenF1 response format") }
    }

    static func retryDate(_ value: String?, now: Date) -> Date {
        JSONHTTPClient.retryDate(value, now: now)
    }
}

// Both providers share the bounded transport, request budget and Retry-After rules.
actor JSONHTTPClient {
    private let transport: any HTTPTransport
    private let gate: RequestGate
    private var blockedUntil: Date?

    init(transport: any HTTPTransport, requestSpacing: Duration) {
        self.transport = transport
        gate = RequestGate(spacing: requestSpacing)
    }

    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("F1MenuBar/0.3.0 (macOS; personal calendar client)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0..<2 {
            if let blockedUntil, blockedUntil > Date() { throw APIError.rateLimited(blockedUntil) }
            try await gate.wait()
            if let blockedUntil, blockedUntil > Date() { throw APIError.rateLimited(blockedUntil) }
            let response = try await transport.send(request)
            try Task.checkCancellation()
            guard response.data.count <= 6_000_000 else { throw APIError.responseTooLarge }
            if response.status == 401 || response.status == 403 { throw APIError.subscriptionRequired }
            if response.status == 429 {
                let until = Self.retryDate(response.retryAfter, now: Date())
                blockedUntil = until
                throw APIError.rateLimited(until)
            }
            if (500...599).contains(response.status), attempt == 0 {
                if response.retryAfter != nil {
                    let until = Self.retryDate(response.retryAfter, now: Date())
                    blockedUntil = until
                    throw APIError.rateLimited(until)
                }
                try await Task.sleep(for: .seconds(2))
                continue
            }
            guard (200...299).contains(response.status) else { throw APIError.http(response.status) }
            return response.data
        }
        throw APIError.invalidResponse
    }

    static func retryDate(_ value: String?, now: Date) -> Date {
        if let value, let seconds = Double(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(max(1, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let value, let date = formatter.date(from: value), date > now { return date }
        return now.addingTimeInterval(60)
    }
}
