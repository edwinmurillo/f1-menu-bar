import Foundation

enum OpenF1HistoryMapper {
    static func map(request: RaceHistoryRequest, session: Int, laps: [HistoricalLapDTO], positions: [HistoricalPositionDTO],
                    drivers: [HistoricalDriverDTO], intervals: [HistoricalIntervalDTO], stints: [HistoricalStintDTO]?,
                    pits: [HistoricalPitDTO]?, control: [HistoricalControlDTO], updatedAt: Date) throws -> RaceHistory {
        guard laps.allSatisfy({ $0.sessionKey == session && (1...200).contains($0.lapNumber) && (0...999).contains($0.driverNumber) &&
                  $0.lapDuration.map { $0.isFinite && $0 > 0 && $0 <= 86_400 } != false }),
              positions.allSatisfy({ $0.sessionKey == session && (1...100).contains($0.position) }),
              drivers.allSatisfy({ $0.sessionKey == session }), intervals.allSatisfy({ $0.sessionKey == session }),
              (stints ?? []).allSatisfy({ $0.sessionKey == session && (1...200).contains($0.lapStart) &&
                  $0.lapEnd.map { (1...200).contains($0) } != false }),
              (pits ?? []).allSatisfy({ $0.sessionKey == session && (1...200).contains($0.lapNumber) }),
              control.allSatisfy({ $0.sessionKey == session }),
              Set(laps.map { "\($0.driverNumber)-\($0.lapNumber)" }).count == laps.count,
              Set(drivers.map(\.driverNumber)).count == drivers.count else { throw APIError.invalidData("inconsistent OpenF1 race history") }
        let numbers = Set(laps.map(\.driverNumber)).union(drivers.map(\.driverNumber)).sorted()
        guard numbers.count <= 100 else { throw APIError.responseTooLarge }
        let roster = numbers.map { number in
            let person = drivers.first { $0.driverNumber == number }
            return RaceHistoryDriver(id: String(number), name: person?.fullName ?? "Driver \(number)",
                abbreviation: person?.nameAcronym ?? String(number), team: person?.teamName ?? "", teamColor: person?.teamColour)
        }
        let grouped = Dictionary(grouping: laps, by: \.driverNumber)
        let positionGroups = Dictionary(grouping: positions, by: \.driverNumber).mapValues { $0.sorted { $0.date < $1.date } }
        let intervalGroups = Dictionary(grouping: intervals, by: \.driverNumber).mapValues { $0.sorted { $0.date < $1.date } }
        let completed = laps.filter { $0.lapDuration != nil }.map(\.lapNumber).max() ?? 0
        var normalized: [RaceHistoryLap] = []
        var best: [Int: Double] = [:]
        for lap in 1...max(completed, 1) where completed > 0 {
            var timings: [RaceHistoryTiming] = []
            for number in numbers {
                let driverLaps = grouped[number] ?? []
                let lastCompleted = driverLaps.filter { $0.lapDuration != nil }.map(\.lapNumber).max() ?? 0
                guard lap <= lastCompleted, let row = driverLaps.first(where: { $0.lapNumber == lap }) else { continue }
                if let duration = row.lapDuration { best[number] = min(best[number] ?? .infinity, duration) }
                // OpenF1 labels lap starts approximate. Sample the most recent
                // position/gap at this driver's lap boundary; never sum lap times
                // into a fictional race gap or carry an old gap through a stoppage.
                let end = row.dateStart.flatMap { start in row.lapDuration.map { start.addingTimeInterval($0) } }
                    ?? driverLaps.first(where: { $0.lapNumber == lap + 1 })?.dateStart
                let position = end.flatMap { time in positionGroups[number]?.last { $0.date <= time }?.position }
                let interval = end.flatMap { time in intervalGroups[number]?.last { $0.date <= time && time.timeIntervalSince($0.date) <= 10 } }
                let gap = interval?.gapToLeader?.normalized ?? (position == 1 ? .seconds(0) : nil)
                let stint = (stints ?? []).filter { $0.driverNumber == number && $0.lapStart <= lap && ($0.lapEnd ?? 200) >= lap }
                    .max { $0.lapStart < $1.lapStart }
                let age = stint.flatMap { stint in stint.tyreAgeAtStart.flatMap { age in
                    (0...200).contains(age) ? age + lap - stint.lapStart + 1 : nil
                } }
                var timing = RaceHistoryTiming(driverID: String(number), position: position, duration: row.lapDuration,
                    bestDuration: best[number], gap: gap, compound: stint?.compound, tyreAge: age,
                    stops: pits.map { $0.filter { $0.driverNumber == number && $0.lapNumber <= lap }.count })
                if let stints {
                    let observed = stints.filter { $0.driverNumber == number && $0.lapStart <= lap }
                        .sorted { $0.lapStart < $1.lapStart }
                    timing.tyreHistory = observed.enumerated().map { index, value in
                        let completed = index < observed.count - 1 ? value.lapEnd.flatMap { end in
                            end >= value.lapStart ? end - value.lapStart + 1 : nil
                        } : nil
                        return TyreHistorySegment(compound: value.compound, completedLaps: completed)
                    }
                }
                timings.append(timing)
            }
            if !timings.isEmpty { normalized.append(RaceHistoryLap(number: lap, timings: timings)) }
        }
        let events = control.enumerated().map { index, row in
            RaceHistoryEvent(id: "\(session)-\(index)", lap: row.lapNumber.flatMap { (1...max(completed, 1)).contains($0) ? $0 : nil },
                date: row.date, category: row.category ?? "", flag: row.flag, message: row.message)
        }
        return RaceHistory(request: request, provider: .openF1, sourceID: String(session), drivers: roster,
                           laps: normalized, events: events, updatedAt: updatedAt)
    }
}
