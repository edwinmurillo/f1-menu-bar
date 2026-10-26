import Foundation

public struct WeekendVictory: Identifiable, Equatable, Sendable {
    public let weekend: RaceWeekend
    public let qualifying: Bool
    public let grandPrix: Bool
    public var id: Int { weekend.id }
}

public enum SeasonStatistics {
    public static func victories(for driver: DriverStanding, in snapshot: SeasonSnapshot) -> [WeekendVictory] {
        eligibleWeekends(in: snapshot).compactMap { weekend in
            let qualifying = !weekend.sessions.contains { $0.isQualifying && $0.isCancelled }
                && matches(weekend.qualifyingWinner, driver: driver)
            let grandPrix = matches(weekend.winner, driver: driver)
            return qualifying || grandPrix ? WeekendVictory(weekend: weekend, qualifying: qualifying, grandPrix: grandPrix) : nil
        }
    }

    public static func victories(for constructor: ConstructorStanding, in snapshot: SeasonSnapshot) -> [WeekendVictory] {
        eligibleWeekends(in: snapshot).compactMap { weekend in
            guard let winner = weekend.winner else { return nil }
            let matches: Bool
            if let expected = constructor.constructorID, let actual = winner.constructorID { matches = expected == actual }
            else { matches = winner.team.caseInsensitiveCompare(constructor.name) == .orderedSame }
            return matches ? WeekendVictory(weekend: weekend, qualifying: false, grandPrix: true) : nil
        }
    }

    private static func eligibleWeekends(in snapshot: SeasonSnapshot) -> [RaceWeekend] {
        snapshot.weekends.filter { $0.year == snapshot.year && !$0.isCancelled && !$0.isMissingFromSchedule && $0.grandPrix?.isCancelled != true }
            .sorted { ($0.sortDate, $0.id) < ($1.sortDate, $1.id) }
    }

    private static func matches(_ winner: RaceWinner?, driver: DriverStanding) -> Bool {
        guard let winner else { return false }
        if let expected = driver.driverID, let actual = winner.driverID { return expected == actual }
        // OpenF1 numbers are scoped by the enclosing season. Older cached Jolpica
        // winners may lack provider IDs; fall back only when an ID is unavailable.
        if let expected = driver.driverNumber, let actual = winner.driverNumber { return expected == actual }
        return winner.driverName.caseInsensitiveCompare(driver.name) == .orderedSame
    }
}
