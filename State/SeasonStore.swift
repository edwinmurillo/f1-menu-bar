import Foundation
import Observation

@MainActor @Observable
public final class SeasonStore {
    public private(set) var snapshot: SeasonSnapshot
    public private(set) var nextSeason: SeasonSnapshot?
    public private(set) var previousSeason: SeasonSnapshot?
    public private(set) var isRefreshing = false
    public private(set) var now: Date
    public private(set) var startupIssue: String?
    public var displayYear: Int?

    @ObservationIgnored private let repository: any SeasonRepository
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var hasStarted = false
    public let policy = SchedulePolicy()

    public init(repository: any SeasonRepository, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository; self.clock = clock
        let date = clock(); now = date
        snapshot = SeasonSnapshot(year: Self.year(at: date))
    }

    public var availableSeasons: [SeasonSnapshot] {
        ([previousSeason, snapshot, nextSeason].compactMap { $0 }).filter { !$0.weekends.isEmpty || $0.year == snapshot.year }.sorted { $0.year < $1.year }
    }
    public var visibleSnapshot: SeasonSnapshot {
        if let displayYear, let selected = availableSeasons.first(where: { $0.year == displayYear }) { return selected }
        if snapshot.weekends.isEmpty, let previousSeason { return previousSeason }
        return snapshot
    }
    public var featured: RaceWeekend? {
        policy.featured(in: snapshot.weekends, now: now) ?? nextSeason.flatMap { policy.featured(in: $0.weekends, now: now) }
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let year = snapshot.year
        let token = generation
        do {
            let cached = try await repository.cached(year: year)
            if generation == token, snapshot.year == year {
                if let cached { snapshot = cached }
                if snapshot.weekends.isEmpty {
                    let previous = try await repository.cached(year: year - 1)
                    if generation == token, snapshot.year == year { previousSeason = previous }
                }
            }
        } catch {
            if generation == token, snapshot.year == year { startupIssue = error.localizedDescription }
        }
        await refresh()
    }

    public func tick() async {
        now = clock()
        if snapshot.year != Self.year(at: now) {
            cancelRefresh()
            previousSeason = snapshot
            snapshot = nextSeason?.year == Self.year(at: now) ? nextSeason! : SeasonSnapshot(year: Self.year(at: now))
            nextSeason = nil; displayYear = nil; lastAttempt = nil
        }
        await refresh()
    }

    public func refresh(force: Bool = false) async {
        if let refreshTask { await refreshTask.value; return }
        let date = clock(); now = date
        let interval = snapshot.weekends.isEmpty || !snapshot.issues.isEmpty ? 5 * 60 : policy.refreshInterval(in: snapshot.weekends, now: date)
        if !force, let lastAttempt, date.timeIntervalSince(lastAttempt) < interval { return }
        lastAttempt = date
        generation += 1
        let token = generation
        isRefreshing = true
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performRefresh(token: token)
        }
        refreshTask = task
        await task.value
        if generation == token { refreshTask = nil; isRefreshing = false }
    }

    public func cancelRefresh() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private func performRefresh(token: Int) async {
        let year = snapshot.year
        do {
            let result = try await repository.refresh(year: year, previous: snapshot) { [weak self] partial in
                await self?.accept(partial, token: token, expectedYear: year)
            }
            guard generation == token, !Task.isCancelled else { return }
            snapshot = result
            if result.scheduleUpdatedAt != nil { startupIssue = nil }
            if policy.shouldCheckNextSeason(result, now: clock()) {
                if nextSeason == nil {
                    let cached = try await repository.cached(year: year + 1)
                    guard generation == token, !Task.isCancelled else { return }
                    nextSeason = cached
                }
                let next = try await repository.refresh(year: year + 1, previous: nextSeason) { [weak self] partial in
                    await self?.acceptNext(partial, token: token, expectedYear: year + 1)
                }
                if generation == token, !Task.isCancelled { nextSeason = next }
            }
        } catch is CancellationError { }
        catch {
            if generation == token { startupIssue = error.localizedDescription }
        }
    }

    private func accept(_ partial: SeasonSnapshot, token: Int, expectedYear: Int) {
        guard generation == token, snapshot.year == expectedYear, partial.year == expectedYear else { return }
        snapshot = partial
    }
    private func acceptNext(_ partial: SeasonSnapshot, token: Int, expectedYear: Int) {
        guard generation == token, partial.year == expectedYear else { return }
        nextSeason = partial
    }
    private static func year(at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.year, from: date)
    }
}
