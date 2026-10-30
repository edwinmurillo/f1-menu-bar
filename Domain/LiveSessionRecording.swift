import Foundation

public struct LiveSessionRecording: Codable, Equatable, Sendable {
    public let sessionID: String
    public var meetingName: String
    public var sessionName: String
    public var updatedAt: Date
    public var laps: [Int: LiveTimingSnapshot]
    /// Practice/qualifying rankings at each newly observed best-lap improvement.
    public var practiceSnapshots: [Int: LiveTimingSnapshot]?
    public var isBestLapSession: Bool {
        sessionName.localizedCaseInsensitiveContains("Practice") || sessionName.localizedCaseInsensitiveContains("Qualifying") ||
            sessionName.localizedCaseInsensitiveContains("Shootout")
    }
    public var recordedStepCount: Int { isBestLapSession ? (practiceSnapshots?.count ?? 0) : laps.count }

    public init(sessionID: String, meetingName: String, sessionName: String, updatedAt: Date, laps: [Int: LiveTimingSnapshot] = [:]) {
        self.sessionID = sessionID; self.meetingName = meetingName; self.sessionName = sessionName
        self.updatedAt = updatedAt; self.laps = laps; self.practiceSnapshots = [:]
    }

    public mutating func record(_ snapshot: LiveTimingSnapshot, at now: Date) {
        guard snapshot.sessionID == sessionID, snapshot.sessionName == sessionName,
              !snapshot.drivers.isEmpty else { return }
        if !isBestLapSession, let lap = snapshot.currentLap, (1...200).contains(lap) {
            updatedAt = now
            laps[lap] = snapshot
        } else {
            if practiceSnapshots == nil { practiceSnapshots = [:] }
            let previous = practiceSnapshots?.max { $0.key < $1.key }?.value
            let priorBest = Dictionary(uniqueKeysWithValues: (previous?.drivers ?? []).map { ($0.id, $0.bestLap.flatMap(LapDuration.seconds)) })
            let improved = snapshot.drivers.contains { driver in
                guard let best = driver.bestLap.flatMap(LapDuration.seconds) else { return false }
                if let old = priorBest[driver.id] ?? nil { return best < old - 0.0005 }
                return true
            }
            guard improved else { return }
            let next = (practiceSnapshots?.keys.max() ?? 0) + 1
            guard next <= 200 else { return }
            var captured = snapshot
            captured.receivedAt = now
            var roster = Dictionary(uniqueKeysWithValues: (previous?.drivers ?? []).map { ($0.id, $0) })
            for driver in snapshot.drivers {
                if driver.bestLap.flatMap(LapDuration.seconds) != nil { roster[driver.id] = driver }
                else if roster[driver.id] == nil { roster[driver.id] = driver }
            }
            captured.drivers = roster.values.sorted { $0.id < $1.id }
            practiceSnapshots?[next] = captured
            updatedAt = now
        }
    }
}
