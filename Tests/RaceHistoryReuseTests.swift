import XCTest
@testable import F1Core

@MainActor final class RaceHistoryReuseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func request(_ id: Int) -> RaceHistoryRequest {
        var weekend = RaceWeekend(id: id, year: 2026, name: "GP \(id)", sessions: [])
        weekend.winner = RaceWinner(driverNumber: 1, driverName: "Winner", team: "Team")
        return RaceHistoryRequest(weekend: weekend, provider: .openF1)
    }
    private func value(_ id: Int, sparse: Bool = false) -> RaceHistory {
        let driver = RaceHistoryDriver(id: "1", name: "Driver", abbreviation: "DRV", team: "Team", teamColor: nil)
        let laps = (sparse ? [9, 14] : [1, 2, 3]).map { lap in
            RaceHistoryLap(number: lap, timings: [RaceHistoryTiming(driverID: "1", position: 1,
                duration: 90, bestDuration: 90, gap: nil, compound: nil, tyreAge: nil, stops: nil)])
        }
        return RaceHistory(request: request(id), provider: .openF1, sourceID: String(id), drivers: [driver], laps: laps,
            events: [], updatedAt: now.addingTimeInterval(-7 * 86_400))
    }
    func testCompletedRacesReuseOldDiskCacheAndRevisitFromMemoryWithoutNetwork() async {
        let repo = ReuseRepository(saved: [value(1), value(2)])
        let clock = now
        let store = RaceHistoryStore(repository: repo, now: { clock })
        await store.load(request(1)); await store.load(request(2)); await store.load(request(1))
        XCTAssertEqual(store.history?.sourceID, "1")
        let counts = await repo.counts()
        XCTAssertEqual(counts.0, 2, "Revisiting a GP must not even re-read its disk cache")
        XCTAssertEqual(counts.1, 0, "Completed history must not expire after one hour")
    }
    func testRefreshExplicitlyBypassesCompletedCache() async {
        let repo = ReuseRepository(saved: [value(1)])
        let store = RaceHistoryStore(repository: repo)
        await store.load(request(1)); await store.load(request(1), force: true)
        let counts = await repo.counts()
        XCTAssertEqual(counts.1, 1)
    }
    func testSparseSavedPositionsAreDetectedAndRepairedEvenForCompletedGP() async {
        let broken = value(1, sparse: true)
        XCTAssertTrue(broken.needsPositionRepair)
        let good = value(1)
        XCTAssertFalse(good.needsPositionRepair)
        let repo = ReuseRepository(saved: [broken], refreshed: good)
        let store = RaceHistoryStore(repository: repo)
        await store.load(request(1))
        XCTAssertEqual(store.history?.laps.map(\.number), [1, 2, 3])
        let counts = await repo.counts()
        XCTAssertEqual(counts.1, 1)
    }
    func testProgressiveCoreAppearsBeforeSlowDetailsFinish() async {
        var core = value(1); core.detailsComplete = false
        let full = value(1)
        let repo = ProgressiveRepository(core: core, full: full)
        let store = RaceHistoryStore(repository: repo)
        let work = Task { await store.load(request(1)) }
        await repo.waitForPreview()
        XCTAssertEqual(store.history?.detailsComplete, false)
        XCTAssertEqual(store.history?.laps.count, 3)
        XCTAssertTrue(store.isLoading)
        await repo.finish()
        await work.value
        XCTAssertFalse(store.isLoading)
        XCTAssertNotEqual(store.history?.detailsComplete, false)
    }
}

private actor ReuseRepository: RaceHistoryRepository {
    let saved: [RaceHistory]
    let refreshed: RaceHistory?
    var reads = 0
    var fetches = 0
    init(saved: [RaceHistory], refreshed: RaceHistory? = nil) { self.saved = saved; self.refreshed = refreshed }
    func cached(_ request: RaceHistoryRequest) -> RaceHistory? { reads += 1; return saved.first { $0.request == request } }
    func fetch(_ request: RaceHistoryRequest) throws -> RaceHistory {
        fetches += 1
        guard let value = refreshed ?? saved.first(where: { $0.request == request }) else { throw APIError.http(404) }
        return value
    }
    func counts() -> (Int, Int) { (reads, fetches) }
}

private actor ProgressiveRepository: RaceHistoryRepository {
    let core: RaceHistory
    let full: RaceHistory
    var previewReady = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    var completion: CheckedContinuation<Void, Never>?
    init(core: RaceHistory, full: RaceHistory) { self.core = core; self.full = full }
    func cached(_ request: RaceHistoryRequest) -> RaceHistory? { nil }
    func fetch(_ request: RaceHistoryRequest) -> RaceHistory { full }
    func fetch(_ request: RaceHistoryRequest, publish: @escaping @Sendable (RaceHistory) async -> Void) async -> RaceHistory {
        await publish(core)
        await withCheckedContinuation { continuation in
            completion = continuation; previewReady = true
            waiters.forEach { $0.resume() }; waiters.removeAll()
        }
        return full
    }
    func waitForPreview() async {
        if previewReady { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish() { completion?.resume(); completion = nil }
}
