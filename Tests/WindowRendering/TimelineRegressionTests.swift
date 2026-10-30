import XCTest
@testable import F1Core

@MainActor final class TimelineRegressionTests: XCTestCase {
    private func driver(id: String = "87", code: String = "BEA", position: Int? = 2,
                        retired: Bool = false) -> LiveDriverTiming {
        LiveDriverTiming(id: id, position: position, name: "Driver \(code)", abbreviation: code,
            team: "Team", teamColor: "FF8000", gap: "+2.000", interval: "+1.000",
            laps: nil, lastLap: "1:20.123", bestLap: "1:19.000", sectors: [], stops: nil,
            inPit: false, retired: retired, knockedOut: false, stints: [])
    }
    private func snapshot(session: String = "race", lap: Int? = 30) -> LiveTimingSnapshot {
        var s = LiveTimingSnapshot()
        s.sessionID = session; s.sessionName = "Race"; s.currentLap = lap; s.totalLaps = 70
        s.drivers = [driver(id: "1", code: "ONE", position: 1), driver(), driver(id: "3", code: "THR", position: 3)]
        return s
    }

    func testObservedRunningDriverOverridesSimulatedRetirement() throws {
        let s = snapshot()
        let race = TimelineRace(snapshot: s, observedLaps: [30: s], seed: 2026)
        let bea = try XCTUnwrap(race.drivers.first { $0.id == "87" })
        let row = TimelineLapRow(driver: bea, lap: 30, observed: s, seed: 2026)
        XCTAssertEqual(bea.positions[29], 2)
        XCTAssertEqual(row.source, .recorded)
        XCTAssertFalse(row.retired)
        XCTAssertEqual(row.position, 2)
        XCTAssertEqual(row.gap, "+2.000")
        XCTAssertEqual(row.lastLap, "1:20.123")
        XCTAssertEqual(row.laps, "—", "Unknown recorded lap counts must not be simulated")
        XCTAssertEqual(row.stops, "—")
    }

    func testRecordedRetirementUsesProviderFlagWithoutChangingLapValues() throws {
        var s = snapshot()
        s.drivers[1] = driver(retired: true)
        let race = TimelineRace(snapshot: s, observedLaps: [:], seed: 2026)
        let row = TimelineLapRow(driver: race.drivers[1], lap: 30, observed: s, seed: 2026)
        XCTAssertTrue(row.retired)
        XCTAssertEqual(race.activeCount(at: 30), 2)
        XCTAssertEqual(row.lastLap, "1:20.123")
        XCTAssertEqual(row.gap, "+2.000")
        XCTAssertNil(row.gapSeconds)
    }

    func testPreviousRaceAndWrongLapCannotSupplyRecordedRowsOrGapSamples() throws {
        let current = snapshot(session: "new", lap: nil)
        let previous = snapshot(session: "old", lap: 10)
        let race = TimelineRace(snapshot: current, observedLaps: [10: previous], seed: 2026)
        XCTAssertNil(TimelineRace.observedSnapshot(at: 10, current: current, saved: [10: previous]))
        let row = TimelineLapRow(driver: race.drivers[0], lap: 10, observed: previous, seed: 2026)
        XCTAssertEqual(row.source, .simulated)
        let sameSessionWrongLap = snapshot(session: "new", lap: 9)
        XCTAssertNil(TimelineRace.observedSnapshot(at: 10, current: current, saved: [10: sameSessionWrongLap]))
        XCTAssertEqual(TimelineLapRow(driver: race.drivers[0], lap: 10,
            observed: sameSessionWrongLap, seed: 2026).source, .simulated)
    }

    func testSingleDriverRetainsAbsoluteRecordedPosition() {
        var s = snapshot()
        s.drivers = [driver(position: 22)]
        let race = TimelineRace(snapshot: s, observedLaps: [:], seed: 2026)
        XCTAssertEqual(race.drivers[0].positions[29], 22)
        XCTAssertEqual(race.positionCount, 22)
        XCTAssertEqual(TimelineLapRow(driver: race.drivers[0], lap: 30, observed: s, seed: 2026).position, 22)
    }

    func testDriverMissingFromCapturedLapStaysUnavailable() {
        let current = snapshot()
        var partial = snapshot(lap: 10)
        partial.drivers = [partial.drivers[0]]
        let race = TimelineRace(snapshot: current, observedLaps: [10: partial], seed: 2026)
        let row = TimelineLapRow(driver: race.drivers[1], lap: 10, observed: partial, seed: 2026)
        XCTAssertNil(race.drivers[1].positions[9])
        XCTAssertEqual(row.source, .unavailable)
        XCTAssertNil(row.position)
        XCTAssertEqual(row.lastLap, "—")
    }

    func testRecordedModeDoesNotReuseAnEarlierSessionOrInventMissingLaps() {
        let old = snapshot(session: "old", lap: 10)
        let next = snapshot(session: "new", lap: nil)
        XCTAssertTrue(RecordedRaceTimeline(current: next, saved: [10: old]).laps.isEmpty)
        var practice = snapshot(session: "practice", lap: nil)
        practice.sessionName = "Practice 1"
        XCTAssertTrue(RecordedRaceTimeline(current: practice, saved: [10: old]).laps.isEmpty)
        let current = snapshot(lap: 34)
        let history = RecordedRaceTimeline(current: current, saved: [30: snapshot(lap: 30), 32: snapshot(lap: 32)])
        XCTAssertEqual(history.laps, [30, 32, 34])
        XCTAssertNil(history.snapshots[31])
    }

    func testConnectionStatusDistinguishesFreshStaleFinishedAndDisconnected() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var data = snapshot()
        data.sessionStatus = "Started"; data.lastTimingUpdate = now
        var state = LiveTimingState(phase: .connected, snapshot: data)
        XCTAssertEqual(LiveTimingConnectionPresentation.status(state, at: now), "Live")
        XCTAssertFalse(LiveTimingConnectionPresentation.isLive(state, at: now.addingTimeInterval(31)))
        XCTAssertTrue(LiveTimingConnectionPresentation.status(state, at: now.addingTimeInterval(31)).contains("outdated"))
        state.snapshot.sessionStatus = "Finished"
        XCTAssertTrue(LiveTimingConnectionPresentation.status(state, at: now).contains("Session finished"))
        state.phase = .stopped
        XCTAssertTrue(LiveTimingConnectionPresentation.status(state, at: now).contains("Disconnected"))
        state.phase = .unavailable
        XCTAssertEqual(LiveTimingConnectionPresentation.status(state, at: now), "Live timing unavailable")
    }
}
