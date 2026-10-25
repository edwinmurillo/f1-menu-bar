import Foundation

public enum WeekendStatus: Equatable, Sendable {
    case raced, current, next, future, resultsPending, cancelled, unavailable
}

public struct SchedulePolicy: Sendable {
    public let resultFocusInterval: TimeInterval
    public init(resultFocusInterval: TimeInterval = 6 * 60 * 60) {
        self.resultFocusInterval = resultFocusInterval
    }

    public func featured(in weekends: [RaceWeekend], now: Date) -> RaceWeekend? {
        weekends.sorted { $0.sortDate < $1.sortDate }.first { weekend in
            guard !weekend.isCancelled, !weekend.isMissingFromSchedule, weekend.winner == nil else { return false }
            if let raceStart = weekend.grandPrix?.start {
                return now < raceStart.addingTimeInterval(resultFocusInterval)
            }
            return (weekend.firstStart ?? .distantFuture) >= now
        }
    }

    public func nextSession(in weekend: RaceWeekend, now: Date) -> RaceSession? {
        weekend.activeSessions.filter { ($0.start ?? .distantPast) > now }
            .min { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// An ongoing weekend is a date-range state, not evidence of a live session.
    public func isOngoing(_ weekend: RaceWeekend, now: Date, timeZone: TimeZone) -> Bool {
        weekend.winner == nil && isWithinWeekendDates(weekend, now: now, timeZone: timeZone)
    }

    /// Standings may still be pending after a GP winner has been published.
    public func isAwaitingStandings(in weekends: [RaceWeekend], context: ChampionshipContext?, now: Date, timeZone: TimeZone) -> Bool {
        weekends.contains { weekend in
            isWithinWeekendDates(weekend, now: now, timeZone: timeZone) &&
            context?.sessionID != weekend.grandPrix?.id
        }
    }

    private func isWithinWeekendDates(_ weekend: RaceWeekend, now: Date, timeZone: TimeZone) -> Bool {
        guard !weekend.isCancelled, !weekend.isMissingFromSchedule,
              let race = weekend.grandPrix, !race.isCancelled, let raceStart = race.start,
              let first = weekend.activeSessions.compactMap(\.start).min() ?? weekend.start else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: first)
        let raceDay = calendar.startOfDay(for: raceStart)
        guard let followingDay = calendar.date(byAdding: .day, value: 1, to: raceDay) else { return false }
        return now >= firstDay && now < followingDay
    }

    public func status(of weekend: RaceWeekend, in weekends: [RaceWeekend], now: Date) -> WeekendStatus {
        if weekend.isCancelled { return .cancelled }
        if weekend.isMissingFromSchedule { return .unavailable }
        if weekend.winner != nil { return .raced }
        if let start = weekend.grandPrix?.start, start <= now { return .resultsPending }
        if featured(in: weekends, now: now)?.id == weekend.id {
            return (weekend.firstStart ?? .distantFuture) <= now ? .current : .next
        }
        return .future
    }

    public func refreshInterval(in weekends: [RaceWeekend], now: Date) -> TimeInterval {
        guard let weekend = featured(in: weekends, now: now) else { return 6 * 60 * 60 }
        if let race = weekend.grandPrix?.start, race <= now { return 5 * 60 }
        if let first = weekend.firstStart, now >= first.addingTimeInterval(-24 * 60 * 60) { return 30 * 60 }
        return 6 * 60 * 60
    }

    public func shouldCheckNextSeason(_ snapshot: SeasonSnapshot, now: Date) -> Bool {
        !snapshot.weekends.isEmpty && featured(in: snapshot.weekends, now: now) == nil &&
        snapshot.weekends.filter { !$0.isCancelled && !$0.isMissingFromSchedule }.allSatisfy { $0.sortDate < now }
    }
}
