import XCTest
@testable import F1Core

@MainActor final class RecordedRaceTimelineTests: XCTestCase {
    func testOnlyObservedLapsFromCurrentRaceArePlotted() {
        func snapshot(session: String, lap: Int) -> LiveTimingSnapshot {
            var value = LiveTimingSnapshot()
            value.sessionID = session
            value.sessionName = "Race"
            value.currentLap = lap
            value.drivers = (1...12).map { position in
                LiveDriverTiming(id: String(position), position: position,
                    name: "Driver \(position)", abbreviation: "D\(position)",
                    team: "Team", teamColor: nil,
                    gap: position == 1 ? nil : "+13.000", interval: nil,
                    laps: lap, lastLap: nil, bestLap: nil, sectors: [],
                    stops: nil, inPit: false, retired: false,
                    knockedOut: false, stints: [])
            }
            return value
        }

        let current = snapshot(session: "current", lap: 4)
        let history = RecordedRaceTimeline(current: current, saved: [
            1: snapshot(session: "previous", lap: 1),
            2: snapshot(session: "current", lap: 2)
        ])
        XCTAssertEqual(history.laps, [2, 4])
        XCTAssertNil(history.snapshots[3])
        XCTAssertEqual(history.topTenDrivers.count, 10)
        XCTAssertEqual(history.topTenDrivers.map(\.id), (1...10).map(String.init))
        XCTAssertEqual(RecordedRaceTimeline.gapSeconds(history.driver("1", at: 4)!), 0)
        XCTAssertEqual(RecordedRaceTimeline.gapSeconds(history.driver("2", at: 4)!), 13)
    }
}
