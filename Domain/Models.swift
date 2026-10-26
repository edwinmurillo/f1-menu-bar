import Foundation

public enum DataProvider: String, Codable, Sendable {
    case openF1 = "openf1"
    case jolpica
}

public struct RaceSession: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let start: Date?
    public let end: Date?
    public let isCancelled: Bool

    public init(id: Int, name: String, start: Date?, end: Date? = nil, isCancelled: Bool = false) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
        self.isCancelled = isCancelled
    }

    public var isGrandPrix: Bool { name.caseInsensitiveCompare("Race") == .orderedSame }
    public var isSprint: Bool { name.caseInsensitiveCompare("Sprint") == .orderedSame }
    public var isQualifying: Bool { name.caseInsensitiveCompare("Qualifying") == .orderedSame }
}

public struct RaceWinner: Codable, Equatable, Sendable {
    public let driverNumber: Int?
    public let driverName: String
    public let team: String
    public var driverID: String? = nil
    public var constructorID: String? = nil
}

public struct RaceWeekend: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let year: Int
    public let name: String
    public let circuit: String
    public let country: String
    public let location: String
    public let start: Date?
    public var sessions: [RaceSession]
    public var isCancelled: Bool
    public var isMissingFromSchedule: Bool
    public var winner: RaceWinner?
    public var qualifyingWinner: RaceWinner?

    public init(id: Int, year: Int, name: String, circuit: String = "", country: String = "", location: String = "", start: Date? = nil, sessions: [RaceSession], isCancelled: Bool = false, isMissingFromSchedule: Bool = false, winner: RaceWinner? = nil, qualifyingWinner: RaceWinner? = nil) {
        self.id = id; self.year = year; self.name = name; self.circuit = circuit
        self.country = country; self.location = location; self.start = start
        self.sessions = sessions; self.isCancelled = isCancelled
        self.isMissingFromSchedule = isMissingFromSchedule; self.winner = winner
        self.qualifyingWinner = qualifyingWinner
    }

    public var grandPrix: RaceSession? { sessions.first(where: \.isGrandPrix) }
    public var hasSprint: Bool { sessions.contains(where: \.isSprint) }
    public var firstStart: Date? { sessions.compactMap(\.start).min() ?? start }
    public var sortDate: Date { grandPrix?.start ?? firstStart ?? .distantFuture }
    public var activeSessions: [RaceSession] { sessions.filter { !$0.isCancelled } }
}

public struct DriverStanding: Codable, Identifiable, Equatable, Sendable {
    public var id: String { driverID ?? "number-\(driverNumber.map(String.init) ?? name)" }
    public var driverID: String? = nil
    public let driverNumber: Int?
    public let position: Int?
    public var positionText: String? = nil
    public let name: String
    public let team: String
    public let teamColor: String?
    public let points: Double
}

public struct ConstructorStanding: Codable, Identifiable, Equatable, Sendable {
    public var id: String { constructorID ?? name }
    public var constructorID: String? = nil
    public let name: String
    public let position: Int?
    public var positionText: String? = nil
    public let drivers: String
    public let color: String?
    public let points: Double
}

public enum DataSection: String, Codable, CaseIterable, Sendable {
    case schedule, results, qualifying, drivers, constructors
}

public struct ChampionshipContext: Codable, Equatable, Sendable {
    public let sessionID: Int
    public let meetingName: String
    public let updatedAt: Date
    public var round: Int? = nil
}

public struct SeasonSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schema: Int = Self.schemaVersion
    public var provider: DataProvider = .openF1
    public let year: Int
    public var weekends: [RaceWeekend] = []
    public var drivers: [DriverStanding] = []
    public var constructors: [ConstructorStanding] = []
    public var scheduleUpdatedAt: Date?
    public var resultsUpdatedAt: Date?
    public var qualifyingUpdatedAt: Date?
    public var driverContext: ChampionshipContext?
    public var constructorContext: ChampionshipContext?
    public var issues: [DataSection: String] = [:]

    public init(year: Int, provider: DataProvider = .openF1) { self.year = year; self.provider = provider }
    public var latestUpdate: Date? {
        [scheduleUpdatedAt, resultsUpdatedAt, qualifyingUpdatedAt, driverContext?.updatedAt, constructorContext?.updatedAt].compactMap { $0 }.max()
    }
}
