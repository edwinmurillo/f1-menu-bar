import Foundation

/// Approximate spatial progress from race timing, never measured car coordinates.
public struct TrackTimingEstimate: Sendable {
    public let lap: Int
    public let leaderNumber: Int
    public let leaderLapTime: Double
    public let progressByNumber: [Int: Double]

    /// Replays the leader's most recently completed lap at twice its recorded speed.
    public static func make(snapshot: LiveTimingSnapshot, playbackSeconds: Double, lap selectedLap: Int? = nil) -> Self? {
        guard ["Race", "Sprint"].contains(snapshot.sessionName ?? ""),
              let currentLap = snapshot.currentLap,
              let leader = snapshot.drivers.first(where: { $0.position == 1 && !$0.isOutOfRunning && !$0.inPit }),
              let leaderNumber = Int(leader.id) else { return nil }
        guard let lapTime = leader.lastLap.flatMap(LapDuration.seconds),
              (45...600).contains(lapTime), playbackSeconds.isFinite else { return nil }
        let duration = lapTime / 2
        let leaderProgress = min(max(playbackSeconds, 0).truncatingRemainder(dividingBy: duration) / duration, 0.999)
        var progress = [leaderNumber: leaderProgress]
        for driver in snapshot.drivers where !driver.isOutOfRunning && !driver.inPit {
            guard let number = Int(driver.id), number != leaderNumber,
                  let gap = driver.gap.flatMap(gapSeconds) else { continue }
            let behind = gap / lapTime
            let fraction = (leaderProgress - behind).truncatingRemainder(dividingBy: 1)
            progress[number] = fraction < 0 ? fraction + 1 : fraction
        }
        return Self(lap: selectedLap ?? max(currentLap - 1, 1), leaderNumber: leaderNumber, leaderLapTime: lapTime,
                    progressByNumber: progress)
    }

    private static func gapSeconds(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
        let value = Double(cleaned) ?? LapDuration.seconds(cleaned)
        guard let value, value.isFinite, (0...7200).contains(value) else { return nil }
        return value
    }
}
