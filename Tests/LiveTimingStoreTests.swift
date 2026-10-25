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
