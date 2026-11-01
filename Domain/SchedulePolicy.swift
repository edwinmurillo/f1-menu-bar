import Foundation

public enum WeekendStatus: Equatable, Sendable {
    case raced, current, next, future, resultsPending, cancelled, unavailable
}

/// Timetable estimates are distinct from published results and live timing.
public enum SessionScheduleStatus: Equatable, Sendable {
    case next, scheduledInProgress, scheduledFinished, startPassed, finished, resultsPending
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

    public func sessionStatus(_ session: RaceSession, in weekend: RaceWeekend, now: Date, timeZone: TimeZone) -> SessionScheduleStatus? {
        guard isWithinWeekendDates(weekend, now: now, timeZone: timeZone), !session.isCancelled else { return nil }
        if session.isGrandPrix && weekend.winner != nil || session.isQualifying && weekend.qualifyingWinner != nil {
            return .finished
        }
        guard let start = session.start else { return nil }
        if start > now {
            return nextSession(in: weekend, now: now)?.id == session.id ? .next : nil
        }
        // Only use a valid, supplied end time; never manufacture a session duration.
        if let end = session.end, end > start {
            if now < end { return .scheduledInProgress }
            return session.isGrandPrix ? .resultsPending : .scheduledFinished
        }
        // Without a supplied end, completion is unknown. Keep the started
        // timetable state distinct from a known end awaiting published results.
        if session.isGrandPrix { return .startPassed }
        // The backup calendar has no end times. Earlier days and sessions followed
        // by another scheduled start can be marked as past timetable entries only.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let isEarlierDay = start < calendar.startOfDay(for: now)
        let laterSessionStarted = weekend.activeSessions.contains {
            guard let later = $0.start else { return false }
            return later > start && later <= now
        }
        return isEarlierDay || laterSessionStarted ? .scheduledFinished : .startPassed
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
