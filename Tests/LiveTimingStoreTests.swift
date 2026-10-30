import XCTest
@testable import F1Core

private actor ControlledLiveFeed: LiveTimingFeed {
    private var callbacks: [@Sendable (LiveTimingState) async -> Void] = []
    private var finishes: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var count: Int { callbacks.count }
    func run(onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async {
        let index = callbacks.count
        callbacks.append(onUpdate)
        await withCheckedContinuation { continuation in
            finishes[index] = continuation
            let ready = waiters.filter { $0.0 <= callbacks.count }
            waiters.removeAll { $0.0 <= callbacks.count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForRuns(_ count: Int) async {
        if callbacks.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func emit(_ state: LiveTimingState, run: Int) async { await callbacks[run](state) }
    func finishAll() { let values = finishes.values; finishes.removeAll(); values.forEach { $0.resume() } }
}

@MainActor final class LiveTimingStoreTests: XCTestCase {
    func testLapHistoryClearsOnNewIdentityBeforeLapOrRosterArrives() async {
        let feed = ControlledLiveFeed()
        let store = LiveTimingStore(feed: feed)
        store.setVisible(true)
        await feed.waitForRuns(1)
        var race = LiveTimingSnapshot()
        race.sessionID = "race-a"; race.sessionName = "Race"; race.currentLap = 20
        race.drivers = [LiveDriverTiming(id: "1", position: 1, name: "Driver", abbreviation: "DRV",
            team: "Team", teamColor: nil, gap: nil, interval: nil, laps: 20,
            lastLap: nil, bestLap: nil, sectors: [], stops: nil, inPit: false,
            retired: false, knockedOut: false, stints: [])]
        await feed.emit(LiveTimingState(phase: .connected, snapshot: race), run: 0)
        XCTAssertEqual(store.lapSnapshots.count, 1)
        // A reconnect without an identity does not establish a new session.
        await feed.emit(LiveTimingState(phase: .connecting), run: 0)
        XCTAssertEqual(store.lapSnapshots.count, 1)
        var next = LiveTimingSnapshot()
        next.sessionID = "race-b"; next.sessionName = "Race"
        await feed.emit(LiveTimingState(phase: .connected, snapshot: next), run: 0)
        XCTAssertTrue(store.lapSnapshots.isEmpty)
        race.sessionID = "race-b"
        await feed.emit(LiveTimingState(phase: .connected, snapshot: race), run: 0)
        XCTAssertEqual(store.lapSnapshots.count, 1)
        next.sessionID = "practice"; next.sessionName = "Practice 1"
        await feed.emit(LiveTimingState(phase: .connected, snapshot: next), run: 0)
        XCTAssertTrue(store.lapSnapshots.isEmpty)
        store.stop()
        await feed.finishAll()
    }

    func testRaceLapLogKeepsObservedLapsAndResetsForNextSession() async {
        let feed = ControlledLiveFeed()
        let store = LiveTimingStore(feed: feed)
        store.setVisible(true)
        await feed.waitForRuns(1)
        func snapshot(session: String, lap: Int, position: Int) -> LiveTimingSnapshot {
            var value = LiveTimingSnapshot()
            value.sessionID = session
            value.sessionName = "Race"
            value.currentLap = lap
            value.drivers = [LiveDriverTiming(id: "44", position: position, name: "Test Driver",
                abbreviation: "TST", team: "Test", teamColor: nil, gap: nil, interval: nil,
                laps: lap, lastLap: nil, bestLap: nil, sectors: [], stops: nil,
                inPit: false, retired: false, knockedOut: false, stints: [])]
            return value
        }
        await feed.emit(LiveTimingState(phase: .connected, snapshot: snapshot(session: "a", lap: 1, position: 3)), run: 0)
        await feed.emit(LiveTimingState(phase: .connected, snapshot: snapshot(session: "a", lap: 2, position: 2)), run: 0)
        XCTAssertEqual(store.lapSnapshots[1]?.drivers.first?.position, 3)
        XCTAssertEqual(store.lapSnapshots[2]?.drivers.first?.position, 2)
        await feed.emit(LiveTimingState(phase: .connected, snapshot: snapshot(session: "b", lap: 1, position: 1)), run: 0)
        XCTAssertEqual(store.lapSnapshots.count, 1)
        XCTAssertEqual(store.lapSnapshots[1]?.drivers.first?.position, 1)
        store.stop()
        await feed.finishAll()
    }

    func testOneConnectionAndLateCancelledUpdatesCannotReplaceReopenedView() async {
        let feed = ControlledLiveFeed()
        let subject = LiveTimingStore(feed: feed)
        subject.setVisible(true)
        subject.setVisible(true)
        await feed.waitForRuns(1)
        let calls = await feed.count
        XCTAssertEqual(calls, 1)
        var first = LiveTimingSnapshot(); first.sessionID = "first"
        await feed.emit(LiveTimingState(phase: .connected, snapshot: first), run: 0)
        subject.setVisible(false)
        XCTAssertEqual(subject.state.phase, .stopped)
        var late = LiveTimingSnapshot(); late.sessionID = "late"
        await feed.emit(LiveTimingState(phase: .connected, snapshot: late), run: 0)
        XCTAssertEqual(subject.state.snapshot.sessionID, "first")
        subject.setVisible(true)
        await feed.waitForRuns(2)
        var current = LiveTimingSnapshot(); current.sessionID = "current"
        await feed.emit(LiveTimingState(phase: .connected, snapshot: current), run: 1)
        await feed.emit(LiveTimingState(phase: .unavailable, snapshot: late), run: 0)
        XCTAssertEqual(subject.state.snapshot.sessionID, "current")
        XCTAssertEqual(subject.state.phase, .connected)
        subject.stop()
        await feed.finishAll()
    }

    func testDisconnectPersistsAcrossVisibilityAndSleepUntilExplicitConnect() async {
        let feed = ControlledLiveFeed()
        let subject = LiveTimingStore(feed: feed)
        subject.setVisible(true)
        await feed.waitForRuns(1)
        subject.disconnect()
        subject.setVisible(false); subject.setVisible(true)
        subject.suspend(); subject.resume()
        XCTAssertFalse(subject.isRunning)
        let count = await feed.count
        XCTAssertEqual(count, 1)
        subject.connect()
        await feed.waitForRuns(2)
        XCTAssertTrue(subject.isRunning)
        subject.setVisible(false)
        subject.resume()
        XCTAssertFalse(subject.isRunning)
        subject.stop()
        await feed.finishAll()
    }

    func testSleepStopsVisibleFeedAndWakeRestartsOnlyVisibleView() async {
        let feed = ControlledLiveFeed()
        let store = LiveTimingStore(feed: feed)
        store.setVisible(true)
        await feed.waitForRuns(1)
        store.suspend()
        XCTAssertFalse(store.isRunning)
        store.resume()
        await feed.waitForRuns(2)
        XCTAssertTrue(store.isRunning)
        store.setVisible(false)
        store.suspend(); store.resume()
        XCTAssertFalse(store.isRunning)
        store.stop()
        await feed.finishAll()
    }
}
