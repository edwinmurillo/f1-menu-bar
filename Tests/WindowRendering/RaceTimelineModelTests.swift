import XCTest
@testable import F1Core

@MainActor final class RaceTimelineModelTests: XCTestCase {
    func testMockGapsConvergeOnLiveFinishGap() {
        let gaps = (47...56).map {
            TimelineRace.mockGapSeconds(lap: $0, position: 8,
                                        finalGap: "+13.000", finalPosition: 8)
        }
        XCTAssertEqual(gaps.first, 3.25)
        XCTAssertEqual(gaps.last, 13)
        XCTAssertTrue(zip(gaps, gaps.dropFirst()).allSatisfy { $0.0 < $0.1 })
        XCTAssertEqual(TimelineRace.mockGapSeconds(lap: 39, position: 8,
                                                   finalGap: "+13.000", finalPosition: 8), 12.6)
        let beforeWindow = TimelineRace.mockGapSeconds(lap: 46, position: 8,
                                                       finalGap: "+13.000", finalPosition: 8)
        XCTAssertEqual(beforeWindow, gaps[0])
        XCTAssertEqual(TimelineRace.mockGapSeconds(lap: 52, position: 1,
                                                   finalGap: nil, finalPosition: 1), 0)
    }

    func testRetirementsEndAtLastRunningPositionAndCompressLaterLaps() {
        var snapshot = LiveTimingSnapshot()
        snapshot.sessionID = "race"
        snapshot.sessionName = "Race"
        snapshot.currentLap = nil // Test simulated laps without a current observed lap.
        snapshot.totalLaps = 56
        let codes = (1...19).map { "D\($0)" } + ["BOT", "COL", "BEA"]
        snapshot.drivers = codes.enumerated().map { index, code in
            LiveDriverTiming(id: String(index + 1), position: index + 1,
                name: code, abbreviation: code, team: "Team", teamColor: nil,
                gap: nil, interval: nil, laps: 56, lastLap: nil, bestLap: nil,
                sectors: [], stops: nil, inPit: false, retired: false,
                knockedOut: false, stints: [])
        }
        for seed in [UInt64(2026), 2027] {
            let race = TimelineRace(snapshot: snapshot, observedLaps: [:], seed: seed)
            XCTAssertEqual(race.topTenDrivers.map(\.id), (1...10).map(String.init))
            for (lap, expected) in [(23, 22), (24, 22), (25, 21), (35, 21),
                                    (36, 20), (48, 20), (49, 19), (56, 19)] {
                XCTAssertEqual(race.activeCount(at: lap), expected)
                let positions = race.drivers.compactMap { $0.positions[lap - 1] }.sorted()
                XCTAssertEqual(positions, Array(1...expected))
            }
            for (code, retirement, lastPosition) in [("BEA", 24, 22), ("COL", 35, 21), ("BOT", 48, 20)] {
                let driver = race.drivers.first { $0.timing.abbreviation == code }
                XCTAssertEqual(driver?.positions[retirement - 1], lastPosition)
                XCTAssertNil(driver?.positions[retirement])
            }
            XCTAssertEqual(race.drivers.first?.positions[55], 1)
            XCTAssertEqual(race.drivers[18].positions[55], 19)
            for driver in race.drivers {
                XCTAssertEqual(Array(driver.positions[51...55]),
                               Array(repeating: driver.positions[55], count: 5))
            }
        }
    }

    func testSparseRetiredRosterDoesNotTryToSwapMissingDrivers() {
        var snapshot = LiveTimingSnapshot()
        snapshot.sessionID = "race"
        snapshot.sessionName = "Race"
        snapshot.currentLap = nil // Test simulated laps without a current observed lap.
        snapshot.drivers = ["BOT", "COL"].enumerated().map { index, code in
            LiveDriverTiming(id: String(index + 1), position: index + 1,
                name: code, abbreviation: code, team: "Team", teamColor: nil,
                gap: nil, interval: nil, laps: nil, lastLap: nil, bestLap: nil,
                sectors: [], stops: nil, inPit: false, retired: true,
                knockedOut: false, stints: [])
        }
        let race = TimelineRace(snapshot: snapshot, observedLaps: [:], seed: 2026)
        XCTAssertEqual(race.activeCount(at: 1), 2)
        XCTAssertEqual(race.activeCount(at: 56), 0)
    }
}
