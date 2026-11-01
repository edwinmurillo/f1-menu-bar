import F1Core
import Foundation

/// Adapts recorded provider values into the one timing presentation. Missing
/// intervals, sectors, retirement and tyre metadata remain unknown.
enum TimingHistoryPresentation {
    static func snapshot(_ history: RaceHistory, lap requested: Int) -> LiveTimingSnapshot {
        var value = LiveTimingSnapshot()
        value.sessionID = "history:\(history.request.key)"
        value.meetingName = history.request.weekend.name
        value.sessionName = history.request.session?.name
        let lap = history.laps.min { abs($0.number - requested) < abs($1.number - requested) }
        value.currentLap = lap?.number; value.totalLaps = history.lastLap
        value.receivedAt = history.updatedAt
        let timings = lap?.timings ?? []
        var rows: [LiveDriverTiming] = []
        for person in history.drivers {
            let timing = timings.first { $0.driverID == person.id }
            let rankingUpdates = history.sourceID.hasPrefix("live:") &&
                ["practice", "qualifying", "shootout"].contains { history.request.session?.name.lowercased().contains($0) == true }
            let driverLap = timing?.completedDriverLaps ?? (rankingUpdates ? nil : lap?.number)
            rows.append(driver(person, timing: timing, timings: timings, lap: driverLap))
        }
        rows.sort { a, b in
            let left = a.position ?? Int.max, right = b.position ?? Int.max
            return left == right ? a.id < b.id : left < right
        }
        value.drivers = rows
        value.messages = history.events.filter { $0.lap == nil || $0.lap! <= (lap?.number ?? 0) }
            .suffix(100).reversed().map { LiveRaceMessage(id: $0.id, date: $0.date, message: $0.message) }
        return value
    }

    private static func driver(_ person: RaceHistoryDriver, timing: RaceHistoryTiming?, timings: [RaceHistoryTiming], lap: Int?) -> LiveDriverTiming {
        var gap: String?, last: String?, best: String?
        if let value = timing?.gap { gap = HistoryFormat.gap(value) }
        if let value = timing?.duration { last = HistoryFormat.duration(value) }
        if let value = timing?.bestDuration { best = HistoryFormat.duration(value) }
        let interval = intervalToAhead(timing, timings: timings)
        let laps: Int? = timing == nil ? nil : lap
        var result = LiveDriverTiming(id: person.id, position: timing?.position, name: person.name,
            abbreviation: person.abbreviation, team: person.team, teamColor: person.teamColor,
            gap: gap, interval: interval, laps: laps, lastLap: last, bestLap: best,
            sectors: [], stops: timing?.stops, inPit: timing?.inPit == true,
            retired: timing?.retired == true, knockedOut: false, stints: [])
        result.pitOut = timing?.pitOut
        result.stopped = timing?.stopped
        result.racingNumber = person.racingNumber ?? (Int(person.id) == nil ? nil : person.id)
        if let segments = timing?.tyreHistory { result.recordedTyreHistory = segments }
        else if let compound = timing?.compound {
            result.recordedTyreHistory = [TyreHistorySegment(compound: compound, completedLaps: timing?.tyreAge)]
        }
        return result
    }

    private static func intervalToAhead(_ timing: RaceHistoryTiming?, timings: [RaceHistoryTiming]) -> String? {
        guard let position = timing?.position, let gap = timing?.gap?.seconds,
              let ahead = timings.first(where: { $0.position == position - 1 }),
              let aheadGap = ahead.gap?.seconds, gap >= aheadGap else { return nil }
        return HistoryFormat.gap(.seconds(gap - aheadGap))
    }

    static func canSimulate(state: LiveTimingState, request: RaceHistoryRequest?, current: RaceHistoryRequest?, usesLive: Bool) -> Bool {
        guard usesLive, state.phase == .connected, let current, current.session?.isGrandPrix == true,
              current.weekend.winner == nil, request == nil || matches(request, current),
              ["Started", "Aborted"].contains(state.snapshot.sessionStatus ?? ""),
              state.snapshot.sessionName == "Race",
              state.snapshot.meetingName?.caseInsensitiveCompare(current.weekend.name) == .orderedSame else { return false }
        return true
    }

    static func matches(_ a: RaceHistoryRequest?, _ b: RaceHistoryRequest?) -> Bool {
        guard let a, let b, a.weekend.year == b.weekend.year,
              a.weekend.name.caseInsensitiveCompare(b.weekend.name) == .orderedSame,
              a.session?.name.caseInsensitiveCompare(b.session?.name ?? "") == .orderedSame,
              let startA = a.session?.start, let startB = b.session?.start else { return false }
        return abs(startA.timeIntervalSince(startB)) < 12 * 3600
    }
}
