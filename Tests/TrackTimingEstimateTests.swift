import XCTest
@testable import F1Core

final class TrackTimingEstimateTests: XCTestCase {
    func testLeaderLapTimeAndNumericGapPlaceCarsAlongRealOutline() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = LiveTimingSnapshot()
        snapshot.sessionName = "Race"; snapshot.sessionStatus = "Started"
        snapshot.currentLap = 12; snapshot.lastTimingUpdate = now
        snapshot.drivers = [
            LiveDriverTiming(id: "1", position: 1, name: "Leader", abbreviation: "LEA", team: "A", teamColor: nil,
                gap: nil, interval: nil, laps: 11, lastLap: "1:40.000", bestLap: nil, sectors: [], stops: nil,
                inPit: false, retired: false, knockedOut: false, stints: []),
            LiveDriverTiming(id: "2", position: 2, name: "Follower", abbreviation: "FOL", team: "B", teamColor: nil,
                gap: "+20.000", interval: nil, laps: 11, lastLap: "1:41.000", bestLap: nil, sectors: [], stops: nil,
                inPit: false, retired: false, knockedOut: false, stints: []),
            LiveDriverTiming(id: "3", position: 3, name: "Lapped", abbreviation: "LAP", team: "C", teamColor: nil,
                gap: "+1 LAP", interval: nil, laps: 10, lastLap: "1:42.000", bestLap: nil, sectors: [], stops: nil,
                inPit: false, retired: false, knockedOut: false, stints: [])
        ]
        let estimate = try XCTUnwrap(TrackTimingEstimate.make(snapshot: snapshot, playbackSeconds: 25))
        XCTAssertEqual(estimate.lap, 11)
        XCTAssertEqual(try XCTUnwrap(estimate.progressByNumber[1]), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(estimate.progressByNumber[2]), 0.3, accuracy: 0.001)
        XCTAssertNil(estimate.progressByNumber[3], "A lap-count gap cannot determine a location")
        let start = try XCTUnwrap(TrackTimingEstimate.make(snapshot: snapshot, playbackSeconds: 0))
        XCTAssertEqual(try XCTUnwrap(start.progressByNumber[1]), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(start.progressByNumber[2]), 0.8, accuracy: 0.001)
        let restart = try XCTUnwrap(TrackTimingEstimate.make(snapshot: snapshot, playbackSeconds: 50))
        XCTAssertEqual(try XCTUnwrap(restart.progressByNumber[1]), 0, accuracy: 0.001)
        snapshot.lastTimingUpdate = now.addingTimeInterval(-3_600)
        let selected = try XCTUnwrap(TrackTimingEstimate.make(snapshot: snapshot, playbackSeconds: 25, lap: 7))
        XCTAssertEqual(selected.lap, 7, "A selected recorded lap must use its own snapshot even after live freshness expires")
        XCTAssertEqual(try XCTUnwrap(selected.progressByNumber[2]), 0.3, accuracy: 0.001)
        snapshot.sessionName = "Practice 1"
        XCTAssertNil(TrackTimingEstimate.make(snapshot: snapshot, playbackSeconds: 25))
    }
}
