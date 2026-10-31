import Foundation

extension RaceWeekend {
    public func hasStartedTimelineSession(at now: Date) -> Bool {
        !isCancelled && !isMissingFromSchedule && activeSessions.contains {
            $0.start.map { $0 <= now } ?? ($0.isGrandPrix && winner != nil)
        }
    }
    /// Selection eligibility does not establish completion or available lap data.
    /// Practice dates must not make a future Grand Prix selectable.
    public func isEligibleForTimeline(at now: Date) -> Bool {
        guard !isCancelled, !isMissingFromSchedule, let race = grandPrix, !race.isCancelled else { return false }
        if let start = race.start { return start <= now }
        return winner != nil
    }
}

public struct RaceHistoryRequest: Codable, Equatable, Sendable {
    public let calendarProvider: DataProvider
    public let weekend: RaceWeekend
    public let sessionID: Int?
    public init(weekend: RaceWeekend, provider: DataProvider, sessionID: Int? = nil) {
        self.weekend = weekend; calendarProvider = provider
        self.sessionID = weekend.sessions.first(where: { $0.id == sessionID })?.isGrandPrix == true ? nil : sessionID
    }
    public var session: RaceSession? {
        if let sessionID { return weekend.sessions.first { $0.id == sessionID } }
        return weekend.grandPrix
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.calendarProvider == rhs.calendarProvider && lhs.weekend.id == rhs.weekend.id &&
            lhs.weekend.year == rhs.weekend.year && lhs.sessionID == rhs.sessionID && lhs.session == rhs.session &&
            lhs.weekend.isCancelled == rhs.weekend.isCancelled && lhs.weekend.isMissingFromSchedule == rhs.weekend.isMissingFromSchedule
    }
    public var key: String {
        let base = "\(calendarProvider.rawValue)-\(weekend.year)-\(weekend.id)"
        return sessionID.map { base + "-session-\($0)" } ?? base
    }
}

public struct RaceHistoryDriver: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let abbreviation: String
    public let team: String
    public let teamColor: String?
}

public struct RaceHistoryTiming: Codable, Equatable, Sendable {
    public let driverID: String
    public let position: Int?
    public let duration: Double?
    public let bestDuration: Double?
    public let gap: RaceHistoryGap?
    public let compound: String?
    public let tyreAge: Int?
    public let stops: Int?
    public var inPit: Bool? = nil
    public var pitOut: Bool? = nil
    public var tyreHistory: [TyreHistorySegment]? = nil
}

public enum RaceHistoryGap: Codable, Equatable, Sendable {
    case seconds(Double), laps(Int)
    public var seconds: Double? { if case .seconds(let value) = self { value } else { nil } }
}

public struct RaceHistoryLap: Codable, Identifiable, Equatable, Sendable {
    public let number: Int
    public let timings: [RaceHistoryTiming]
    public var recordedAt: Date? = nil
    public var id: Int { number }
}

public struct RaceHistoryEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let lap: Int?
    public let date: Date?
    public let category: String
    public let flag: String?
    public let message: String
}

public struct RaceHistory: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schema = Self.schemaVersion
    public let request: RaceHistoryRequest
    public let provider: DataProvider
    public let sourceID: String
    public let drivers: [RaceHistoryDriver]
    public let laps: [RaceHistoryLap]
    public let events: [RaceHistoryEvent]
    public let updatedAt: Date
    public var limitations: [String] = []
    /// nil is a legacy fully-loaded snapshot; false is a progressive preview.
    public var detailsComplete: Bool? = nil
    public var hasConnectedPositions: Bool {
        var prior: [String: Int] = [:]
        for lap in laps {
            for row in lap.timings where row.position != nil {
                if prior[row.driverID] == lap.number - 1 { return true }
                prior[row.driverID] = lap.number
            }
        }
        return false
    }
    public var needsPositionRepair: Bool { !laps.isEmpty && lastLap > 1 && !hasConnectedPositions }
    public var lastLap: Int { laps.last?.number ?? 0 }
    public var positionsCount: Int {
        max(drivers.count, laps.flatMap(\.timings).compactMap(\.position).max() ?? 1)
    }
    public var isValid: Bool {
        guard schema == Self.schemaVersion, drivers.count <= 100, laps.count <= 200, events.count <= 5_000,
              Set(drivers.map(\.id)).count == drivers.count,
              laps.map(\.number) == Array(Set(laps.map(\.number))).sorted() else { return false }
        let ids = Set(drivers.map(\.id))
        return laps.allSatisfy { lap in
            (1...200).contains(lap.number) && lap.timings.count <= 100 &&
                Set(lap.timings.map(\.driverID)).count == lap.timings.count && lap.timings.allSatisfy { row in
                    ids.contains(row.driverID) && row.position.map { (1...100).contains($0) } != false &&
                        row.duration.map { $0.isFinite && $0 >= 0 && $0 <= 86_400 } != false &&
                        row.bestDuration.map { $0.isFinite && $0 >= 0 && $0 <= 86_400 } != false &&
                        row.gap.map { gap in
                            switch gap {
                            case .seconds(let value): value.isFinite && value >= 0 && value <= 86_400
                            case .laps(let count): (1...200).contains(count)
                            }
                        } != false &&
                        row.tyreAge.map { (0...400).contains($0) } != false && row.stops.map { (0...200).contains($0) } != false
                }
        }
    }
}

public protocol RaceHistoryRepository: Sendable {
    func cached(_ request: RaceHistoryRequest) async throws -> RaceHistory?
    func fetch(_ request: RaceHistoryRequest) async throws -> RaceHistory
    func fetch(_ request: RaceHistoryRequest, publish: @escaping @Sendable (RaceHistory) async -> Void) async throws -> RaceHistory
}

extension RaceHistoryRepository {
    public func fetch(_ request: RaceHistoryRequest, publish: @escaping @Sendable (RaceHistory) async -> Void) async throws -> RaceHistory {
        try await fetch(request)
    }
}

public enum LapDuration {
    public static func seconds(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]),
              minutes.isFinite, minutes >= 0, minutes < 1_000, seconds.isFinite,
              seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }
}
