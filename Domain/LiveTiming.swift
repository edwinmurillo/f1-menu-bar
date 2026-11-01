import Foundation

public enum LiveConnectionPhase: Equatable, Sendable {
    case stopped, connecting, connected, reconnecting, unavailable
}

public struct LiveTyreStint: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let compound: String?
    public let tyreAge: Int?
    public let initialAge: Int?
    public let isNew: Bool?
}

public struct TyreHistorySegment: Codable, Equatable, Sendable {
    public let compound: String?
    /// Reported laps driven on this set so far; nil when unavailable.
    public let completedLaps: Int?
    public init(compound: String?, completedLaps: Int?) {
        self.compound = compound; self.completedLaps = completedLaps
    }
}

public struct LiveDriverTiming: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let position: Int?
    public let name: String
    public let abbreviation: String
    public let team: String
    public let teamColor: String?
    public let gap: String?
    public let interval: String?
    public let laps: Int?
    public let lastLap: String?
    public let bestLap: String?
    public let sectors: [String]
    public let stops: Int?
    public let inPit: Bool
    public let retired: Bool
    public let knockedOut: Bool
    public let stints: [LiveTyreStint]
    public var pitOut: Bool? = nil
    public var stopped: Bool? = nil
    public var racingNumber: String? = nil
    public var recordedTyreHistory: [TyreHistorySegment]? = nil
    public var isOutOfRunning: Bool { retired || (stopped == true && !inPit && pitOut != true) }
    public init(id: String, position: Int?, name: String, abbreviation: String, team: String, teamColor: String?,
        gap: String?, interval: String?, laps: Int?, lastLap: String?, bestLap: String?, sectors: [String],
        stops: Int?, inPit: Bool, retired: Bool, knockedOut: Bool, stints: [LiveTyreStint], pitOut: Bool? = nil,
        stopped: Bool? = nil, racingNumber: String? = nil, recordedTyreHistory: [TyreHistorySegment]? = nil) {
        self.id = id; self.position = position; self.name = name; self.abbreviation = abbreviation
        self.team = team; self.teamColor = teamColor; self.gap = gap; self.interval = interval
        self.laps = laps; self.lastLap = lastLap; self.bestLap = bestLap; self.sectors = sectors
        self.stops = stops; self.inPit = inPit; self.retired = retired; self.knockedOut = knockedOut
        self.stints = stints; self.pitOut = pitOut; self.stopped = stopped; self.racingNumber = racingNumber
        self.recordedTyreHistory = recordedTyreHistory
    }
    public var currentTyre: LiveTyreStint? { stints.last }
    public var tyreHistory: [TyreHistorySegment] {
        if let recordedTyreHistory { return recordedTyreHistory }
        let ordered = stints.sorted { $0.id < $1.id }
        return ordered.map { stint in
            let completed = stint.tyreAge.flatMap { total in
                stint.initialAge.map { max(0, total - $0) }
            }
            return TyreHistorySegment(compound: stint.compound, completedLaps: completed)
        }
    }
}

public struct LiveRaceMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date?
    public let message: String
    public init(id: String, date: Date?, message: String) {
        self.id = id; self.date = date; self.message = message
    }
}

public struct LiveSessionClock: Codable, Equatable, Sendable {
    public let remainingAtReference: TimeInterval
    public let referenceUTC: Date
    public let extrapolating: Bool

    public init?(remaining: String?, referenceUTC: Date?, extrapolating: Bool?) {
        guard let remaining, let referenceUTC, let extrapolating else { return nil }
        let parts = remaining.split(separator: ":")
        guard parts.count == 3, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              let seconds = Int(parts[2]), (0...24).contains(hours), (0...59).contains(minutes),
              (0...59).contains(seconds) else { return nil }
        remainingAtReference = TimeInterval(hours * 3600 + minutes * 60 + seconds)
        self.referenceUTC = referenceUTC
        self.extrapolating = extrapolating
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, remainingAtReference - (extrapolating ? max(0, now.timeIntervalSince(referenceUTC)) : 0))
    }
}

public struct LiveTimingSnapshot: Codable, Equatable, Sendable {
    public var sessionID: String?
    public var meetingName: String?
    public var sessionName: String?
    public var sessionStatus: String?
    public var trackStatus: String?
    public var trackStatusCode: String?
    public var currentLap: Int?
    public var totalLaps: Int?
    public var airTemperature: String?
    public var trackTemperature: String?
    public var drivers: [LiveDriverTiming] = []
    public var messages: [LiveRaceMessage] = []
    public var receivedAt: Date?
    /// Only timestamped TimingData deltas establish fresh timing, never a subscription snapshot or ping.
    public var lastTimingUpdate: Date?
    public var sessionClock: LiveSessionClock?
    public init() {}

    public var hasFinished: Bool { sessionStatus.map { ["Finished", "Finalised", "Ends"].contains($0) } ?? false }
    public func hasFreshTiming(at now: Date) -> Bool {
        guard sessionStatus == "Started", let lastTimingUpdate else { return false }
        let age = now.timeIntervalSince(lastTimingUpdate)
        return age >= -5 && age <= 30
    }
}

public struct LiveTimingState: Equatable, Sendable {
    public var phase: LiveConnectionPhase
    public var snapshot: LiveTimingSnapshot
    public var message: String?
    public var retryAt: Date?
    public init(phase: LiveConnectionPhase = .stopped, snapshot: LiveTimingSnapshot = LiveTimingSnapshot(), message: String? = nil, retryAt: Date? = nil) {
        self.phase = phase; self.snapshot = snapshot; self.message = message; self.retryAt = retryAt
    }
}
