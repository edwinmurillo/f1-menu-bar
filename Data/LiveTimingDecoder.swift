import Foundation
import CoreFoundation

/// A bounded JSON value shared by the SignalR envelope and its sparse topic updates.
indirect enum LiveJSON: Equatable, Sendable {
    case object([String: LiveJSON]), array([LiveJSON]), string(String), number(Double), bool(Bool), null

    init(_ value: Any, depth: Int = 0) throws {
        guard depth <= 24 else { throw LiveFeedError.invalidData }
        switch value {
        case let values as [String: Any]:
            guard values.count <= 4096 else { throw LiveFeedError.invalidData }
            self = .object(try values.mapValues { try LiveJSON($0, depth: depth + 1) })
        case let values as [Any]:
            guard values.count <= 4096 else { throw LiveFeedError.invalidData }
            self = .array(try values.map { try LiveJSON($0, depth: depth + 1) })
        case let value as String:
            guard value.utf8.count <= 8192 else { throw LiveFeedError.invalidData }
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .bool(value.boolValue) }
            else { self = .number(value.doubleValue) }
        case is NSNull: self = .null
        default: throw LiveFeedError.invalidData
        }
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= SignalRFrames.maximumBytes else { throw LiveFeedError.tooLarge }
        return try LiveJSON(JSONSerialization.jsonObject(with: data))
    }
    subscript(_ key: String) -> LiveJSON { entries[key] ?? .null }
    var entries: [String: LiveJSON] {
        switch self {
        case .object(let values): values
        case .array(let values): Dictionary(uniqueKeysWithValues: values.enumerated().map { (String($0.offset), $0.element) })
        default: [:]
        }
    }
    var array: [LiveJSON] { if case .array(let values) = self { return values }; return [] }
    var text: String? {
        switch self {
        case .string(let value): return value.isEmpty ? nil : String(value.prefix(300))
        case .number(let value) where value.isFinite && abs(value) < 1e10: return value == value.rounded() ? String(Int(value)) : String(value)
        default: return nil
        }
    }
    var int: Int? { text.flatMap(Int.init).flatMap { (0...100000).contains($0) ? $0 : nil } }
    var bool: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return ["true", "1"].contains(value.lowercased()) ? true : ["false", "0"].contains(value.lowercased()) ? false : nil
        case .number(let value): return value == 1 ? true : value == 0 ? false : nil
        default: return nil
        }
    }
    func merged(with patch: LiveJSON) throws -> LiveJSON {
        guard case .object(let updates) = patch else { return patch }
        var result = entries
        for key in updates["_deleted"]?.array.compactMap(\.text) ?? [] { result.removeValue(forKey: key) }
        for (key, value) in updates where key != "_deleted" {
            result[key] = try (result[key] ?? .null).merged(with: value)
        }
        guard result.count <= 4096 else { throw LiveFeedError.tooLarge }
        return .object(result)
    }
    var ordered: [(String, LiveJSON)] {
        entries.filter { Int($0.key) != nil }.sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
    }
    var retainedBytes: Int {
        switch self {
        case .object(let values): values.reduce(0) { $0 + $1.key.utf8.count + $1.value.retainedBytes + 32 }
        case .array(let values): values.reduce(0) { $0 + $1.retainedBytes + 16 }
        case .string(let value): value.utf8.count + 16
        default: 16
        }
    }
}

struct SignalRFrames {
    static let maximumBytes = 1_048_576
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [LiveJSON] {
        guard buffer.count + data.count <= Self.maximumBytes else { throw LiveFeedError.tooLarge }
        buffer.append(data)
        var messages: [LiveJSON] = []
        while let separator = buffer.firstIndex(of: 0x1e) {
            let part = Data(buffer[..<separator])
            buffer.removeSubrange(...separator)
            if !part.isEmpty { messages.append(try LiveJSON.decode(part)) }
        }
        return messages
    }
}

func liveDate(_ text: String?) -> Date? {
    guard let text else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}

struct LiveTimingReducer {
    static let topics = ["SessionInfo", "SessionStatus", "ExtrapolatedClock", "TrackStatus", "DriverList", "TimingData", "TimingAppData", "LapCount", "RaceControlMessages", "WeatherData"]
    private var topics: [String: LiveJSON] = [:]
    private var timestamps: [String: Date] = [:]
    private(set) var lastTimingUpdate: Date?
    private var receivedAt: Date?

    mutating func seed(_ value: LiveJSON, receivedAt: Date) throws {
        // Every subscription starts from an authoritative full snapshot, including after reconnects.
        self = LiveTimingReducer()
        for topic in Self.topics {
            if let data = value.entries[topic] { topics[topic] = data }
        }
        self.receivedAt = receivedAt
        try boundState()
    }

    mutating func apply(topic: String, value: LiveJSON, timestamp: Date?, receivedAt: Date) throws {
        guard Self.topics.contains(topic) else { return }
        if let timestamp, let previous = timestamps[topic], timestamp < previous { return }
        if topic == "SessionInfo", let newID = identity(value),
           let previous = identity(topics[topic] ?? .null), newID != previous {
            self = LiveTimingReducer()
        }
        topics[topic] = try (topics[topic] ?? .null).merged(with: value)
        if let timestamp { timestamps[topic] = timestamp }
        if topic == "TimingData", let timestamp { lastTimingUpdate = timestamp }
        self.receivedAt = receivedAt
        try boundState()
    }

    private func identity(_ info: LiveJSON) -> String? { info["Key"].text ?? info["Path"].text }

    private mutating func boundState() throws {
        // Reject unexpected growth; only the recent race-control messages need a rolling history.
        for topic in ["DriverList", "TimingData", "TimingAppData"] {
            let root = topics[topic] ?? .null
            let lines = topic == "DriverList" ? root : root["Lines"]
            guard lines.entries.count <= 100 else { throw LiveFeedError.tooLarge }
            if topic == "TimingAppData" {
                guard lines.entries.values.allSatisfy({ $0["Stints"].entries.count <= 100 }) else { throw LiveFeedError.tooLarge }
            }
        }
        if let messages = topics["RaceControlMessages"]?["Messages"] {
            topics["RaceControlMessages"] = .object(["Messages": .object(Dictionary(uniqueKeysWithValues: messages.ordered.suffix(40)))])
        }
        guard topics.values.reduce(0, { $0 + $1.retainedBytes }) <= SignalRFrames.maximumBytes else { throw LiveFeedError.tooLarge }
    }

    func snapshot() -> LiveTimingSnapshot {
        let info = topics["SessionInfo"] ?? .null
        let roster = topics["DriverList"] ?? .null
        let timing = topics["TimingData"]?["Lines"] ?? .null
        let tyres = topics["TimingAppData"]?["Lines"] ?? .null
        var result = LiveTimingSnapshot()
        result.sessionID = identity(info)
        result.meetingName = info["Meeting"]["Name"].text
        result.sessionName = info["Name"].text ?? info["Type"].text
        result.sessionStatus = topics["SessionStatus"]?["Status"].text
        result.trackStatus = topics["TrackStatus"]?["Message"].text
        result.trackStatusCode = topics["TrackStatus"]?["Status"].text
        result.currentLap = topics["LapCount"]?["CurrentLap"].int
        result.totalLaps = topics["LapCount"]?["TotalLaps"].int
        result.airTemperature = topics["WeatherData"]?["AirTemp"].text
        result.trackTemperature = topics["WeatherData"]?["TrackTemp"].text
        result.receivedAt = receivedAt
        result.lastTimingUpdate = lastTimingUpdate
        let clock = topics["ExtrapolatedClock"] ?? .null
        result.sessionClock = LiveSessionClock(remaining: clock["Remaining"].text,
            referenceUTC: liveDate(clock["Utc"].text), extrapolating: clock["Extrapolating"].bool)
        let numbers = Set(roster.entries.keys).union(timing.entries.keys).filter { Int($0) != nil }
        result.drivers = numbers.map { number in
            let person = roster[number], line = timing[number]
            let stints = tyres[number]["Stints"].ordered.map { index, stint in
                LiveTyreStint(id: Int(index) ?? 0, compound: stint["Compound"].text?.uppercased(),
                    tyreAge: stint["TotalLaps"].int, initialAge: stint["StartLaps"].int, isNew: stint["New"].bool)
            }
            let fullName = person["FullName"].text ?? [person["FirstName"].text, person["LastName"].text].compactMap { $0 }.joined(separator: " ")
            var driver = LiveDriverTiming(id: number, position: line["Position"].int, name: fullName.isEmpty ? "Driver \(number)" : fullName,
                abbreviation: person["Tla"].text ?? number, team: person["TeamName"].text ?? "", teamColor: person["TeamColour"].text,
                gap: line["GapToLeader"].text, interval: line["IntervalToPositionAhead"]["Value"].text,
                laps: line["NumberOfLaps"].int, lastLap: line["LastLapTime"]["Value"].text,
                bestLap: line["BestLapTime"]["Value"].text, sectors: (0..<3).map { line["Sectors"][String($0)]["Value"].text ?? "—" },
                stops: line["NumberOfPitStops"].int, inPit: line["InPit"].bool == true, retired: line["Retired"].bool == true,
                knockedOut: line["KnockedOut"].bool == true, stints: stints)
            driver.pitOut = line["PitOut"].bool
            driver.stopped = line["Stopped"].bool
            return driver
        }.sorted { ($0.position ?? .max, Int($0.id) ?? .max) < ($1.position ?? .max, Int($1.id) ?? .max) }
        result.messages = (topics["RaceControlMessages"]?["Messages"].ordered ?? []).reversed().compactMap { key, value in
            guard let text = value["Message"].text else { return nil }
            return LiveRaceMessage(id: key, date: liveDate(value["Utc"].text), message: text)
        }
        return result
    }
}

struct LiveTimingHub {
    enum Event { case handshake, snapshot, data, none }
    private(set) var handshaken = false
    private(set) var subscribed = false
    private(set) var reducer = LiveTimingReducer()
    private var pending: [(LiveJSON, Date)] = []
    private var pendingBytes = 0

    mutating func consume(_ envelope: LiveJSON, receivedAt: Date) throws -> Event {
        guard case .object = envelope else { throw LiveFeedError.invalidData }
        if !handshaken {
            guard envelope.entries.isEmpty else { throw LiveFeedError.invalidData }
            handshaken = true
            return .handshake
        }
        switch envelope["type"].int {
        case 1:
            guard envelope["target"].text == "feed" else { return .none }
            if !subscribed {
                pendingBytes += envelope.retainedBytes
                guard pending.count < 128, pendingBytes <= SignalRFrames.maximumBytes else { throw LiveFeedError.tooLarge }
                pending.append((envelope, receivedAt))
                return .none
            }
            return try apply(envelope, receivedAt: receivedAt) ? .data : .none
        case 3:
            guard envelope["invocationId"].text == "1", !subscribed else { return .none }
            guard envelope["error"].text == nil, case .object = envelope["result"] else { throw LiveFeedError.invalidData }
            try reducer.seed(envelope["result"], receivedAt: receivedAt)
            subscribed = true
            for (value, date) in pending { _ = try apply(value, receivedAt: date) }
            pending.removeAll(); pendingBytes = 0
            return .snapshot
        case 7: throw LiveFeedError.closed
        default: return .none
        }
    }
    private mutating func apply(_ envelope: LiveJSON, receivedAt: Date) throws -> Bool {
        let arguments = envelope["arguments"].array
        guard arguments.count >= 2, let topic = arguments.first?.text, LiveTimingReducer.topics.contains(topic) else { return false }
        try reducer.apply(topic: topic, value: arguments[1], timestamp: arguments.count > 2 ? liveDate(arguments[2].text) : nil, receivedAt: receivedAt)
        return true
    }
}
