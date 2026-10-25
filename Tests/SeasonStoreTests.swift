import XCTest
@testable import F1Core

actor ControlledRepository: SeasonRepository {
    private var requests = 0
    private var pending: [Int: CheckedContinuation<SeasonSnapshot, Never>] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    private let holdCache: Bool
    private var pendingCache: CheckedContinuation<SeasonSnapshot?, Never>?
    private var cacheObservers: [CheckedContinuation<Void, Never>] = []
    init(holdCache: Bool = false) { self.holdCache = holdCache }
    func cached(year: Int) async -> SeasonSnapshot? {
        guard holdCache else { return nil }
        return await withCheckedContinuation { continuation in
            pendingCache = continuation
            cacheObservers.forEach { $0.resume() }
            cacheObservers.removeAll()
        }
    }
    func waitForCacheRead() async {
        if pendingCache != nil { return }
        await withCheckedContinuation { cacheObservers.append($0) }
    }
    func finishCache(name: String) {
        pendingCache?.resume(returning: Self.snapshot(name: name))
        pendingCache = nil
    }
    func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        requests += 1
        let number = requests
        let value = await withCheckedContinuation { continuation in
            pending[number] = continuation
            let ready = observers.filter { $0.0 <= requests }
            observers.removeAll { $0.0 <= requests }
            ready.forEach { $0.1.resume() }
        }
        // Deliberately publish even after cancellation to exercise the stale-result guard.
        await publish(value)
        return value
    }
    func waitForRequests(_ count: Int) async {
        if requests >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func finish(_ request: Int, name: String) {
        pending.removeValue(forKey: request)?.resume(returning: Self.snapshot(name: name))
    }
    private static func snapshot(name: String) -> SeasonSnapshot {
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [RaceWeekend(id: 1, year: 2026, name: name, sessions: [RaceSession(id: 1, name: "Race", start: Fixtures.now.addingTimeInterval(10000))])]
        snapshot.scheduleUpdatedAt = Fixtures.now
        return snapshot
    }
    func count() -> Int { requests }
}

@MainActor
final class SeasonStoreTests: XCTestCase {
    func testLateStartupCacheCannotOverwriteFreshNetworkData() async {
        let repository = ControlledRepository(holdCache: true)
        let store = SeasonStore(repository: repository, clock: { Fixtures.now })
        let startup = Task { await store.start() }
        await repository.waitForCacheRead()
        let refresh = Task { await store.refresh(force: true) }
        await repository.waitForRequests(1)
        await repository.finish(1, name: "Fresh network schedule")
        await refresh.value
        await repository.finishCache(name: "Old cached schedule")
        await startup.value
        XCTAssertEqual(store.snapshot.weekends.first?.name, "Fresh network schedule")
        let requests = await repository.count()
        XCTAssertEqual(requests, 1)
    }

    func testLateCancelledRefreshCannotReplaceNewerSnapshot() async {
        let repository = ControlledRepository()
        let store = SeasonStore(repository: repository, clock: { Fixtures.now })
        let first = Task { await store.refresh(force: true) }
        await repository.waitForRequests(1)
        store.cancelRefresh()
        let second = Task { await store.refresh(force: true) }
        await repository.waitForRequests(2)
        await repository.finish(2, name: "New schedule")
        await second.value
        await repository.finish(1, name: "Obsolete schedule")
        await first.value
        XCTAssertEqual(store.snapshot.weekends.first?.name, "New schedule")
        XCTAssertFalse(store.isRefreshing)
    }

    func testOverlappingRefreshesShareOneRequest() async {
        let repository = ControlledRepository()
        let store = SeasonStore(repository: repository, clock: { Fixtures.now })
        let first = Task { await store.refresh(force: true) }
        await repository.waitForRequests(1)
        var second: Task<Void, Never>?
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            second = Task { @MainActor in
                started.resume()
                await store.refresh(force: true)
            }
        }
        let requestCount = await repository.count()
        XCTAssertEqual(requestCount, 1)
        await repository.finish(1, name: "Shared snapshot")
        await first.value
        await second?.value
        XCTAssertEqual(store.snapshot.weekends.first?.name, "Shared snapshot")
    }
}
