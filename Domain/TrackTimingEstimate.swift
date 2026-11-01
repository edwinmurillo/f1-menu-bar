import Foundation

/// Approximate spatial progress from race timing, never measured car coordinates.
public struct TrackTimingEstimate: Sendable {
    public let lap: Int
    public let leaderNumber: Int
    public let leaderLapTime: Double
    public let progressByNumber: [Int: Double]

    public static func make(snapshot: LiveTimingSnapshot, lapStartedAt: Date?, observedLap: Int?, now: Date) -> Self? {
        guard ["Race", "Sprint"].contains(snapshot.sessionName ?? ""),
              snapshot.hasFreshTiming(at: now), let lap = snapshot.currentLap,
              observedLap == lap, let lapStartedAt,
              let leader = snapshot.drivers.first(where: { $0.position == 1 && !$0.isOutOfRunning && !$0.inPit }),
              let leaderNumber = Int(leader.id) else { return nil }
        let lapTimes = [leader.lastLap, leader.bestLap].compactMap { $0.flatMap(LapDuration.seconds) }
        guard let lapTime = lapTimes.first(where: { (45...600).contains($0) }) else { return nil }
        let elapsed = now.timeIntervalSince(lapStartedAt)
        guard elapsed >= 0, elapsed <= lapTime * 1.2 else { return nil }
        let leaderProgress = min(elapsed / lapTime, 0.999)
        var progress = [leaderNumber: leaderProgress]
        for driver in snapshot.drivers where !driver.isOutOfRunning && !driver.inPit {
            guard let number = Int(driver.id), number != leaderNumber,
                  let gap = driver.gap.flatMap(gapSeconds) else { continue }
            let behind = gap / lapTime
            let fraction = (leaderProgress - behind).truncatingRemainder(dividingBy: 1)
            progress[number] = fraction < 0 ? fraction + 1 : fraction
        }
        return Self(lap: lap, leaderNumber: leaderNumber, leaderLapTime: lapTime,
                    progressByNumber: progress)
    }

    private static func gapSeconds(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
        let value = Double(cleaned) ?? LapDuration.seconds(cleaned)
        guard let value, value.isFinite, (0...7200).contains(value) else { return nil }
        return value
    }
}
