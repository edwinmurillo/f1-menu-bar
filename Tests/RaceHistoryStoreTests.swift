import XCTest
@testable import F1Core

@MainActor final class RaceHistoryStoreTests: XCTestCase {
    func testNewGPRejectsOldResponseEvenWhenOldRequestIgnoresCancellation() async {
        let repository = ControlledHistoryRepository()
        let store = RaceHistoryStore(repository: repository)
        let first = request(1); let second = request(2)
        let a = Task { await store.load(first) }
        await repository.waitFor(1)
        let b = Task { await store.load(second) }
        await repository.waitFor(2)
        await repository.finish(second)
        await b.value
        XCTAssertEqual(store.history?.request, second)
        await repository.finish(first)
        await a.value
        XCTAssertEqual(store.history?.request, second)
        XCTAssertFalse(store.isLoading)
    }
    func testReturningToCancelledGPStartsAnotherLoad() async {
        let repository = ControlledHistoryRepository()
        let store = RaceHistoryStore(repository: repository)
        let selected = request(1)
        let first = Task { await store.load(selected) }
        await repository.waitFor(1)
        store.cancel()
        await repository.finish(selected)
        await first.value
        XCTAssertNil(store.history)
        let returning = Task { await store.load(selected) }
        await repository.waitFor(2)
        await repository.finish(selected)
        await returning.value
        XCTAssertEqual(store.history?.request, selected)
        XCTAssertFalse(store.isLoading)
    }

    func testFailedRefreshPreservesCachedHistoryAndExposesIssue() async {
        let repository = ControlledHistoryRepository(cached: request(1))
        let store = RaceHistoryStore(repository: repository, now: { Date(timeIntervalSince1970: 1_900_000_000) })
        let task = Task { await store.load(request(1)) }
        await repository.waitFor(1)
        XCTAssertEqual(store.history?.request, request(1))
        await repository.fail(request(1))
        await task.value
        XCTAssertEqual(store.history?.request, request(1))
        XCTAssertNotNil(store.issue)
    }
    private func request(_ id: Int) -> RaceHistoryRequest {
        RaceHistoryRequest(weekend: RaceWeekend(id: id, year: 2026, name: "GP \(id)", sessions: []), provider: .openF1)
    }
}

private actor ControlledHistoryRepository: RaceHistoryRepository {
    private var pending: [String: CheckedContinuation<RaceHistory, any Error>] = [:]
    private var calls = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    let saved: RaceHistoryRequest?
    init(cached: RaceHistoryRequest? = nil) { saved = cached }
    func cached(_ request: RaceHistoryRequest) -> RaceHistory? { saved == request ? value(request) : nil }
    func fetch(_ request: RaceHistoryRequest) async throws -> RaceHistory {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.key] = continuation; calls += 1
            let ready = waiters.filter { $0.0 <= calls }; waiters.removeAll { $0.0 <= calls }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitFor(_ count: Int) async {
        if calls >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func finish(_ request: RaceHistoryRequest) { pending.removeValue(forKey: request.key)?.resume(returning: value(request)) }
    func fail(_ request: RaceHistoryRequest) { pending.removeValue(forKey: request.key)?.resume(throwing: APIError.http(503)) }
    private func value(_ request: RaceHistoryRequest) -> RaceHistory {
        RaceHistory(request: request, provider: .openF1, sourceID: request.key, drivers: [],
            laps: [RaceHistoryLap(number: 1, timings: [])], events: [], updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
