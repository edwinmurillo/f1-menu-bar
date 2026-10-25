import Foundation

/// Switches complete provider snapshots; never joins providers' race IDs or points.
public actor FallbackSeasonRepository: SeasonRepository {
    private let primary: any SeasonRepository
    private let fallback: any SeasonRepository

    public init(primary: any SeasonRepository, fallback: any SeasonRepository) {
        self.primary = primary; self.fallback = fallback
    }

    public func cached(year: Int) async throws -> SeasonSnapshot? {
        var values: [SeasonSnapshot] = []
        var failure: (any Error)?
        for repository in [primary, fallback] {
            do { if let value = try await repository.cached(year: year) { values.append(value) } }
            catch is CancellationError { throw CancellationError() }
            catch { failure = error }
        }
        if let saved = values.max(by: { ($0.latestUpdate ?? .distantPast) < ($1.latestUpdate ?? .distantPast) }) { return saved }
        if let failure { throw failure }
        return nil
    }

    public func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        let primaryPrevious = try await prior(for: .openF1, repository: primary, year: year, previous: previous)
        let first = try await primary.refresh(year: year, previous: primaryPrevious) { partial in
            if previous?.provider != .jolpica, !partial.weekends.isEmpty { await publish(partial) }
        }
        try Task.checkCancellation()
        if first.issues.isEmpty {
            await publish(first)
            return first
        }
        let fallbackPrevious = try await prior(for: .jolpica, repository: fallback, year: year, previous: previous)
        let second = try await fallback.refresh(year: year, previous: fallbackPrevious) { partial in
            if !partial.weekends.isEmpty, Self.quality(partial) >= Self.quality(first) { await publish(partial) }
        }
        try Task.checkCancellation()
        var result = Self.quality(second) >= Self.quality(first) ? second : first
        if result.weekends.isEmpty {
            result.issues[.schedule] = "OpenF1: \(first.issues[.schedule] ?? "unavailable") Jolpica: \(second.issues[.schedule] ?? "calendar not published yet")"
        }
        await publish(result)
        return result
    }

    private func prior(for provider: DataProvider, repository: any SeasonRepository, year: Int, previous: SeasonSnapshot?) async throws -> SeasonSnapshot? {
        if previous?.provider == provider, previous?.year == year { return previous }
        do { return try await repository.cached(year: year) }
        catch is CancellationError { throw CancellationError() }
        catch { return nil } // A damaged cache must not stop an online refresh.
    }

    private static func quality(_ value: SeasonSnapshot) -> Int {
        guard !value.weekends.isEmpty else { return 0 }
        let dates: [(DataSection, Date?)] = [(.schedule, value.scheduleUpdatedAt), (.results, value.resultsUpdatedAt),
            (.drivers, value.driverContext?.updatedAt), (.constructors, value.constructorContext?.updatedAt)]
        return 100 + dates.reduce(0) { score, entry in
            score + (entry.1 == nil ? 0 : value.issues[entry.0] == nil ? 10 : 1)
        }
    }
}
