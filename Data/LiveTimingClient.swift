import Foundation

public protocol LiveTimingFeed: Sendable {
    func run(onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async
}

enum LiveFeedError: Error, Sendable {
    case invalidData, tooLarge, closed, timedOut, rejected(Int, Date?)
    var message: String {
        switch self {
        case .invalidData: "The live feed returned an unsupported response."
        case .tooLarge: "The live feed exceeded the app’s data limit."
        case .closed: "The live timing connection closed."
        case .timedOut: "The live feed stopped responding."
        case .rejected(let status, _):
            switch status {
            case 401: "F1 requires authentication for this connection. Free live timing is unavailable."
            case 403: "F1 declined this connection. Live timing is unavailable."
            case 429: "F1 is limiting requests. Please wait before reconnecting."
            default: "Live timing is temporarily unavailable (HTTP \(status))."
            }
        }
    }
}

struct LiveRetryPolicy {
    static let delays: [TimeInterval] = [2, 5, 15]
    static func retryAfter(_ value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(min(seconds, 365 * 86400))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

/// Owns one anonymous connection. A separate local archive stores observed lap snapshots.
public actor F1LiveTimingClient: LiveTimingFeed {
    private var activeSessions: LiveTimingSessions?
    private var activeID: UUID?
    private var blockedUntil: Date?
    public init() {}

    public func run(onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async {
        activeSessions?.cancel()
        activeSessions = nil
        let id = UUID()
        activeID = id
        if let blockedUntil, blockedUntil > Date() {
            await onUpdate(LiveTimingState(phase: .unavailable, message: "Please wait before reconnecting to F1.", retryAt: blockedUntil))
            return
        }
        let sessions = LiveTimingSessions()
        activeSessions = sessions
        defer {
            sessions.cancel()
            if activeID == id { activeSessions = nil; activeID = nil }
        }
        await withTaskCancellationHandler {
            var last = LiveTimingSnapshot()
            var failures = 0
            while !Task.isCancelled && activeID == id {
                await onUpdate(LiveTimingState(phase: .connecting, snapshot: last))
                let connection = LiveTimingConnection(sessions: sessions)
                let started = Date()
                do {
                    try await connection.run(onUpdate: onUpdate)
                    return
                } catch {
                    guard !Task.isCancelled, activeID == id else { return }
                    let latest = await connection.snapshot
                    if latest.sessionID != nil { last = latest }
                    let feedError = error as? LiveFeedError
                    let message = feedError?.message ?? "Could not connect to F1 live timing. Check your connection."
                    if case .rejected(let status, let retryAt) = feedError,
                       [401, 403, 429].contains(status) || retryAt != nil {
                        blockedUntil = max(retryAt ?? .distantPast, Date().addingTimeInterval(120))
                        await onUpdate(LiveTimingState(phase: .unavailable, snapshot: last, message: message, retryAt: blockedUntil))
                        return
                    }
                    if case .invalidData = feedError {
                        await onUpdate(LiveTimingState(phase: .unavailable, snapshot: last, message: message)); return
                    }
                    if case .tooLarge = feedError {
                        await onUpdate(LiveTimingState(phase: .unavailable, snapshot: last, message: message)); return
                    }
                    if Date().timeIntervalSince(started) >= 60 { failures = 0 }
                    guard failures < LiveRetryPolicy.delays.count else {
                        await onUpdate(LiveTimingState(phase: .unavailable, snapshot: last, message: message)); return
                    }
                    let delay = LiveRetryPolicy.delays[failures]
                    failures += 1
                    await onUpdate(LiveTimingState(phase: .reconnecting, snapshot: last, message: message, retryAt: Date().addingTimeInterval(delay)))
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                }
            }
        } onCancel: { sessions.cancel() }
    }
}

/// Short resource deadlines belong to finite HTTP requests, not the upgraded WebSocket.
/// Both sessions share the same cancellation owner; cookies are forwarded explicitly in memory.
private struct LiveTimingSessions: Sendable {
    let negotiation: URLSession
    let stream: URLSession

    init() {
        let httpConfiguration = Self.configuration()
        httpConfiguration.timeoutIntervalForRequest = 20
        httpConfiguration.timeoutIntervalForResource = 30
        negotiation = URLSession(configuration: httpConfiguration, delegate: LiveSessionDelegate(), delegateQueue: nil)
        // Retain Foundation's long-lived resource timeout. The protocol watchdog bounds
        // connection setup and stops an unresponsive stream independently.
        stream = URLSession(configuration: Self.configuration(), delegate: LiveSessionDelegate(), delegateQueue: nil)
    }

    private static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "F1MenuBar/0.4.2 (personal live timing)"]
        return configuration
    }

    func cancel() {
        negotiation.invalidateAndCancel()
        stream.invalidateAndCancel()
    }
}

private final class LiveSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward negotiation cookies or connection identifiers to another endpoint.
        completionHandler(nil)
    }
}

private actor LiveTimingConnection {
    private let sessions: LiveTimingSessions
    private var hub = LiveTimingHub()
    private var frames = SignalRFrames()
    private var dirty = false
    private var lastMessage = Date()
    private var lastPing = Date()
    private var connectedAt = Date()
    var snapshot: LiveTimingSnapshot { hub.reducer.snapshot() }
    init(sessions: LiveTimingSessions) { self.sessions = sessions }

    func run(onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async throws {
        let headers = try await negotiate()
        try Task.checkCancellation()
        var components = URLComponents(string: "wss://livetiming.formula1.com/signalrcore")!
        components.queryItems = [URLQueryItem(name: "id", value: headers.token)]
        var request = URLRequest(url: components.url!)
        if let cookie = headers.cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        request.setValue("F1MenuBar/0.4.2 (personal live timing)", forHTTPHeaderField: "User-Agent")
        let socket = sessions.stream.webSocketTask(with: request)
        socket.maximumMessageSize = SignalRFrames.maximumBytes
        socket.resume()
        connectedAt = Date(); lastMessage = connectedAt; lastPing = connectedAt
        try await withTaskCancellationHandler {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.send(["protocol": "json", "version": 1], socket: socket)
                        try await self.receive(socket: socket, onUpdate: onUpdate)
                    }
                    group.addTask { try await self.keepAlive(socket: socket, onUpdate: onUpdate) }
                    defer { group.cancelAll(); socket.cancel(with: .goingAway, reason: nil) }
                    try await group.next()
                }
            } catch {
                if let response = socket.response as? HTTPURLResponse, response.statusCode >= 400 {
                    throw LiveFeedError.rejected(response.statusCode, LiveRetryPolicy.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: Date()))
                }
                throw error
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }

    private func negotiate() async throws -> (token: String, cookie: String?) {
        let url = URL(string: "https://livetiming.formula1.com/signalrcore/negotiate")!
        let (options, _) = try await http(url: url, method: "OPTIONS")
        try Task.checkCancellation()
        // A 405 OPTIONS response still supplies load-balancer affinity. Access denials are never bypassed.
        guard (200..<300).contains(options.statusCode) || options.statusCode == 405 else { throw refusal(options) }
        let cookie = affinityCookie(options)
        let (response, data) = try await http(url: URL(string: url.absoluteString + "?negotiateVersion=1")!, method: "POST", cookie: cookie)
        guard (200..<300).contains(response.statusCode) else { throw refusal(response) }
        let body = try LiveJSON.decode(data)
        guard case .string(let token) = body["connectionToken"], !token.isEmpty, token.utf8.count <= 8192,
              body["availableTransports"].array.contains(where: { $0["transport"].text == "WebSockets" }) else {
            throw LiveFeedError.invalidData
        }
        return (token, affinityCookie(response) ?? cookie)
    }

    private func http(url: URL, method: String, cookie: String? = nil) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if method == "POST" { request.httpBody = Data() }
        let (bytes, response) = try await sessions.negotiation.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw LiveFeedError.invalidData }
        guard response.expectedContentLength <= 65536 else { throw LiveFeedError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65536 else { throw LiveFeedError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (response, data)
    }

    private func refusal(_ response: HTTPURLResponse) -> LiveFeedError {
        .rejected(response.statusCode, LiveRetryPolicy.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: Date()))
    }
    private func affinityCookie(_ response: HTTPURLResponse) -> String? {
        guard let url = response.url else { return nil }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter { ["AWSALBCORS", "AWSALB"].contains($0.name) }
        return cookies.isEmpty ? nil : HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    private func send(_ message: [String: Any], socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let string = String(data: data, encoding: .utf8) else { throw LiveFeedError.invalidData }
        try await socket.send(.string(string + "\u{1e}"))
    }

    private func receive(socket: URLSessionWebSocketTask, onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async throws {
        while !Task.isCancelled {
            let message = try await socket.receive()
            try Task.checkCancellation()
            let data: Data
            switch message {
            case .data(let bytes): data = bytes
            case .string(let string): data = Data(string.utf8)
            @unknown default: throw LiveFeedError.invalidData
            }
            lastMessage = Date()
            for envelope in try frames.append(data) {
                switch try hub.consume(envelope, receivedAt: lastMessage) {
                case .handshake:
                    try await send(["type": 1, "invocationId": "1", "target": "Subscribe", "arguments": [LiveTimingReducer.topics]], socket: socket)
                case .snapshot:
                    dirty = true
                    await publish(onUpdate)
                case .data: dirty = true
                case .none: break
                }
            }
        }
        throw CancellationError()
    }

    private func keepAlive(socket: URLSessionWebSocketTask, onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: .seconds(1))
            let now = Date()
            guard now.timeIntervalSince(lastMessage) < 45,
                  hub.subscribed || now.timeIntervalSince(connectedAt) < 20 else { throw LiveFeedError.timedOut }
            if hub.handshaken && now.timeIntervalSince(lastPing) >= 10 {
                try await send(["type": 6], socket: socket)
                lastPing = now
            }
            if dirty { await publish(onUpdate) }
        }
    }
    private func publish(_ onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async {
        dirty = false
        await onUpdate(LiveTimingState(phase: .connected, snapshot: hub.reducer.snapshot()))
    }
}
