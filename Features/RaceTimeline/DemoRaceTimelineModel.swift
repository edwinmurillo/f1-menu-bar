import F1Core
import SwiftUI

/// Unobserved laps are a local fixture. Observed laps keep their F1 timing positions.
struct TimelineRace {
    struct Driver: Identifiable {
        let timing: LiveDriverTiming
        let sessionID: String?
        let color: Color
        let retirementLap: Int?
        var positions: [Int?]
        var retiredLaps: Set<Int> = []
        var id: String { timing.id }
        var finish: Int? { positions.last ?? nil }
    }

    let sessionID: String?
    let laps = 56
    let mockCautionLaps = [2...3, 50...52]
    let mockSafetyCarLaps = [25...28]
    let mockRedFlagLaps = [42]
    let mockRetirementLaps = ["BOT": 48, "COL": 35, "BEA": 24]
    var drivers: [Driver]

    func activeCount(at lap: Int) -> Int {
        guard (1...laps).contains(lap) else { return 0 }
        return drivers.filter { $0.positions[lap - 1] != nil && !$0.retiredLaps.contains(lap) }.count
    }

    var positionCount: Int { max(drivers.count, drivers.flatMap { $0.positions.compactMap { $0 } }.max() ?? 1) }

    var topTenDrivers: [Driver] {
        Array(drivers.sorted {
            ($0.timing.position ?? .max, Int($0.id) ?? .max) <
            ($1.timing.position ?? .max, Int($1.id) ?? .max)
        }.prefix(10))
    }

    static func mockGapSeconds(lap: Int, position: Int, finalGap: String?, finalPosition: Int?) -> Double {
        if position == 1 { return 0 }
        let ordinaryGap = Double(position - 1) * 1.8
        guard lap >= 40 else { return ordinaryGap }
        let cleaned = finalGap?.trimmingCharacters(in: CharacterSet(charactersIn: "+s ")) ?? ""
        let finishGap = Double(cleaned) ?? Double(max((finalPosition ?? position) - 1, 0)) * 1.8
        let openingGap = finishGap == 0 ? ordinaryGap * 0.25 : finishGap * 0.25
        if lap < 47 {
            let blend = min(1, Double(lap - 40) / 6)
            return ordinaryGap + (openingGap - ordinaryGap) * blend
        }
        let progress = Double(min(lap, 56) - 47) / 9
        return openingGap + (finishGap - openingGap) * progress
    }

    init(snapshot: LiveTimingSnapshot, observedLaps: [Int: LiveTimingSnapshot], seed: UInt64) {
        sessionID = snapshot.sessionID
        let palette = ["55D6C2", "E63946", "446BFF", "FF9F34", "E5D74B", "E889B2", "4BAFD2"]
        let roster = snapshot.drivers.sorted {
            ($0.position ?? .max, Int($0.id) ?? .max) < ($1.position ?? .max, Int($1.id) ?? .max)
        }
        drivers = roster.enumerated().map { index, timing in
            Driver(timing: timing, sessionID: snapshot.sessionID,
                   color: Presentation.color(hex: timing.teamColor ?? palette[index % palette.count]),
                   retirementLap: ["BOT": 48, "COL": 35, "BEA": 24][timing.abbreviation],
                   positions: Array(repeating: nil, count: 56))
        }
        guard !drivers.isEmpty else { return }

        // Build backwards from the real finishers. A retiree rejoins the mock order
        // at their last completed lap, in its last active position, then is absent
        // from every later lap. The running positions stay contiguous.
        var order = drivers.indices.filter { drivers[$0].retirementLap == nil }
        var random = SeededRandom(seed: seed)
        for lap in stride(from: laps, through: 1, by: -1) {
            if order.count > 1 && lap < 52 && !mockCautionLaps.contains(where: { $0.contains(lap) }) &&
               !mockSafetyCarLaps.contains(where: { $0.contains(lap) }) {
                for _ in 0..<random.next(upperBound: 4) {
                    let index = random.next(upperBound: order.count - 1)
                    order.swapAt(index, index + 1)
                }
            }
            if let retiring = drivers.indices.first(where: { drivers[$0].retirementLap == lap }) {
                order.append(retiring)
            }
            for (position, driverIndex) in order.enumerated() {
                drivers[driverIndex].positions[lap - 1] = position + 1
            }
        }
        // Real observations take precedence over every simulated position,
        // including a mock retirement. A missing driver stays unknown for a
        // captured lap; do not fill it with a simulated classification.
        for lap in 1...laps {
            guard let observed = Self.observedSnapshot(at: lap, current: snapshot, saved: observedLaps) else { continue }
            for index in drivers.indices {
                let actual = observed.drivers.first { $0.id == drivers[index].id }
                drivers[index].positions[lap - 1] = actual?.position
                if actual?.retired == true { drivers[index].retiredLaps.insert(lap) }
            }
        }
    }

    static func observedSnapshot(at lap: Int, current: LiveTimingSnapshot,
                                 saved: [Int: LiveTimingSnapshot]) -> LiveTimingSnapshot? {
        guard current.sessionName == "Race", let sessionID = current.sessionID else { return nil }
        if current.currentLap == lap, !current.drivers.isEmpty { return current }
        guard let value = saved[lap], value.sessionID == sessionID,
              value.sessionName == "Race", value.currentLap == lap else { return nil }
        return value
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next(upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

struct TimelineLapRow: Identifiable {
    let timing: LiveDriverTiming
    let position: Int?
    let gap: String
    let lastLap: String
    let bestLap: String
    let tyre: String
    let tyreAge: String
    let laps: String
    let stops: String
    enum Source: String { case recorded = "Recorded", simulated = "Simulated", unavailable = "Unavailable" }
    let source: Source
    var recorded: Bool { source == .recorded }
    let retired: Bool
    var id: String { timing.id }
    var sortPosition: Int { position ?? .max }
    var sortName: String { timing.name }
    var sortLastLap: Int { Self.timeMilliseconds(lastLap) ?? .max }
    var sortBestLap: Int { Self.timeMilliseconds(bestLap) ?? .max }
    var bestLapMilliseconds: Int? { Self.timeMilliseconds(bestLap) }
    var sortLaps: Int { Int(laps) ?? .max }
    var sortStops: Int { Int(stops) ?? .max }
    var sortTyre: String { tyre }
    var gapSeconds: Double? {
        guard !retired else { return nil }
        if position == 1 || gap == "Leader" { return 0 }
        let cleaned = gap.trimmingCharacters(in: CharacterSet(charactersIn: "+s "))
        return Double(cleaned)
    }
    var sortGap: Double {
        if position == 1 || gap == "Leader" { return 0 }
        if retired && position == nil { return .infinity }
        if let lap = gap.split(separator: " ").last, lap.hasSuffix("L"),
           let count = Double(lap.dropLast()) { return count * 1_000 }
        return Double(gap.trimmingCharacters(in: CharacterSet(charactersIn: "+s"))) ?? .infinity
    }

    init(driver: TimelineRace.Driver, lap: Int, observed: LiveTimingSnapshot?, seed: UInt64) {
        let matching = observed.flatMap { value -> LiveTimingSnapshot? in
            guard let sessionID = driver.sessionID, value.sessionID == sessionID,
                  value.sessionName == "Race", value.currentLap == lap else { return nil }
            return value
        }
        if let actual = matching?.drivers.first(where: { $0.id == driver.id }) {
            timing = actual
            source = .recorded
            position = actual.position
            retired = actual.retired
            gap = actual.gap ?? "—"
            lastLap = actual.lastLap ?? "—"
            bestLap = actual.bestLap ?? "—"
            tyre = actual.currentTyre?.compound ?? "—"
            tyreAge = actual.currentTyre?.tyreAge.map { "\($0) laps" } ?? "Age unknown"
            laps = actual.laps.map(String.init) ?? "—"
            stops = actual.stops.map(String.init) ?? "—"
        } else if matching != nil {
            timing = driver.timing
            source = .unavailable
            position = nil; retired = false
            gap = "—"; lastLap = "—"; bestLap = "—"; tyre = "—"
            tyreAge = "Age unknown"; laps = "—"; stops = "—"
        } else {
            timing = driver.timing
            source = .simulated
            position = driver.positions.indices.contains(lap - 1) ? driver.positions[lap - 1] : nil
            retired = driver.retirementLap.map { lap >= $0 } ?? false
            let completed = min(lap, driver.retirementLap ?? lap)
            lastLap = retired ? "—" : Self.mockTime(driverID: driver.id, lap: lap, seed: seed).display
            bestLap = (1...completed).map { Self.mockTime(driverID: driver.id, lap: $0, seed: seed) }
                .min { $0.milliseconds < $1.milliseconds }?.display ?? "—"
            let mockGap = TimelineRace.mockGapSeconds(lap: lap, position: position ?? max(driver.timing.position ?? 1, 1),
                                                      finalGap: driver.timing.gap,
                                                      finalPosition: driver.timing.position)
            gap = retired ? "DNF" : position == 1 ? "Leader" : String(format: "+%.1fs", mockGap)
            tyre = completed < 18 ? "SOFT" : completed < 39 ? "MEDIUM" : "HARD"
            tyreAge = "\(completed < 18 ? completed : completed < 39 ? completed - 17 : completed - 38) laps"
            laps = String(completed)
            stops = completed < 18 ? "0" : completed < 39 ? "1" : "2"
        }
    }

    private static func mockTime(driverID: String, lap: Int, seed: UInt64) -> (milliseconds: Int, display: String) {
        var random = SeededRandom(seed: seed ^ UInt64(lap * 1000 + (Int(driverID) ?? 0)))
        let seconds = 34 + random.next(upperBound: 10)
        let fraction = random.next(upperBound: 1000)
        return (seconds * 1000 + fraction, String(format: "1:%02d.%03d", seconds, fraction))
    }

    private static func timeMilliseconds(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Double(parts[1]),
              seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60_000 + Int((seconds * 1_000).rounded())
    }
}
