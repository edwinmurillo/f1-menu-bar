import Foundation

public enum LiveRecordingHistory {
    public static func matches(_ recording: LiveSessionRecording, request: RaceHistoryRequest) -> Bool {
        guard recording.isValid, let session = request.session,
              recording.meetingName.caseInsensitiveCompare(request.weekend.name) == .orderedSame,
              session.name.caseInsensitiveCompare(recording.sessionName) == .orderedSame,
              let start = session.start else { return false }
        return recording.updatedAt.timeIntervalSince(start) >= -6 * 3600 &&
            recording.updatedAt.timeIntervalSince(start) <= 24 * 3600
    }

    public static func make(_ recording: LiveSessionRecording, request: RaceHistoryRequest) -> RaceHistory? {
        guard matches(recording, request: request) else { return nil }
        let isPractice = recording.isBestLapSession
        let useBestRanking = isPractice && !recording.isQualifyingSession
        let snapshots = (isPractice ? recording.practiceSnapshots ?? [:] : recording.laps).sorted { $0.key < $1.key }
        guard !snapshots.isEmpty else { return nil }
        let latestDrivers = snapshots.flatMap { $0.value.drivers }
        let roster = Dictionary(grouping: latestDrivers, by: \.id).compactMap { id, rows -> RaceHistoryDriver? in
            guard let driver = rows.last else { return nil }
            return RaceHistoryDriver(id: id, name: driver.name, abbreviation: driver.abbreviation,
                team: driver.team, teamColor: driver.teamColor)
        }.sorted { $0.id < $1.id }
        let laps = snapshots.map { number, snapshot in
            let best = snapshot.drivers.compactMap { driver -> (String, Double)? in
                driver.bestLap.flatMap(LapDuration.seconds).map { (driver.id, $0) }
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
            let ranked = Dictionary(uniqueKeysWithValues: best.enumerated().map { ($0.element.0, $0.offset + 1) })
            let leader = best.first?.1
            return RaceHistoryLap(number: number, timings: snapshot.drivers.map { driver in
                let bestTime = driver.bestLap.flatMap(LapDuration.seconds)
                var timing = RaceHistoryTiming(driverID: driver.id,
                    position: useBestRanking ? ranked[driver.id] : driver.position,
                    duration: driver.lastLap.flatMap(LapDuration.seconds),
                    bestDuration: bestTime,
                    gap: useBestRanking ? bestTime.flatMap { time in leader.map { .seconds(max(0, time - $0)) } } : gap(driver.gap),
                    compound: driver.currentTyre?.compound,
                    tyreAge: driver.currentTyre?.tyreAge, stops: driver.stops, inPit: driver.inPit)
                timing.pitOut = driver.pitOut
                timing.tyreHistory = driver.tyreHistory
                return timing
            }, recordedAt: isPractice ? snapshot.receivedAt : nil)
        }
        return RaceHistory(request: request, provider: .openF1, sourceID: "live:\(recording.sessionID)",
            drivers: roster, laps: laps, events: [], updatedAt: recording.updatedAt,
            limitations: [isPractice
                ? "Recorded best-lap updates from the personal live timing stream. Earlier updates were not reconstructed."
                : "Recorded locally from the personal live timing stream. Earlier laps were not reconstructed."],
            detailsComplete: true)
    }

    private static func gap(_ text: String?) -> RaceHistoryGap? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return .seconds(seconds) }
        if let seconds = LapDuration.seconds(value) { return .seconds(seconds) }
        return nil
    }
}
