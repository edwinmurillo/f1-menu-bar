import Foundation

public actor HistoricalRaceRepository: RaceHistoryRepository {
    let openF1: OpenF1Client
    let jolpica: JolpicaClient
    let cache: RaceHistoryCache
    private let now: @Sendable () -> Date

    public init(openF1: OpenF1Client, jolpica: JolpicaClient, cache: RaceHistoryCache,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.openF1 = openF1; self.jolpica = jolpica; self.cache = cache; self.now = now
    }
    public func cached(_ request: RaceHistoryRequest) async throws -> RaceHistory? { try await cache.load(request) }
    public func fetch(_ request: RaceHistoryRequest) async throws -> RaceHistory {
        try await fetch(request, publish: { _ in })
    }
    public func fetch(_ request: RaceHistoryRequest, publish: @escaping @Sendable (RaceHistory) async -> Void) async throws -> RaceHistory {
        guard (1950...9999).contains(request.weekend.year), !request.weekend.isCancelled,
              !request.weekend.isMissingFromSchedule else { return empty(request, provider: request.calendarProvider) }
        guard let selectedSession = request.session, !selectedSession.isCancelled else { return empty(request, provider: request.calendarProvider) }
        if let start = selectedSession.start, start > now() { return empty(request, provider: request.calendarProvider) }
        var primary: RaceHistory?
        var primaryIssue: String?
        do {
            let candidate = try await openHistory(request, publish: publish)
            if !candidate.laps.isEmpty { primary = candidate }
        } catch is CancellationError { throw CancellationError() }
        catch { primaryIssue = error.localizedDescription }
        var value: RaceHistory
        if let primary { value = primary }
        else if selectedSession.isGrandPrix {
            do {
                value = try await jolpicaHistory(request)
                if primaryIssue != nil { value.limitations.insert("OpenF1 history unavailable. Showing Jolpica lap history.", at: 0) }
            } catch is CancellationError { throw CancellationError() }
            catch { throw APIError.invalidData("OpenF1: \(primaryIssue ?? "no lap history returned"). Jolpica: \(error.localizedDescription)") }
        } else {
            if let primaryIssue { throw APIError.invalidData("OpenF1 session history: \(primaryIssue)") }
            value = empty(request, provider: .openF1)
        }
        value.detailsComplete = true
        try Task.checkCancellation()
        guard value.isValid else { throw APIError.invalidData("invalid normalized race history") }
        do { try await cache.save(value) }
        catch is CancellationError { throw CancellationError() }
        catch { value.limitations.append("The history could not be saved for offline use.") }
        return value
    }
    func empty(_ request: RaceHistoryRequest, provider: DataProvider) -> RaceHistory {
        RaceHistory(request: request, provider: provider, sourceID: "unavailable", drivers: [], laps: [], events: [], updatedAt: now())
    }
    func timestamp() -> Date { now() }

    private func openSession(_ request: RaceHistoryRequest) async throws -> Int? {
        guard let selected = request.session else { return nil }
        if request.calendarProvider == .openF1, selected.id > 0 { return selected.id }
        guard let start = selected.start else { return nil }
        let sessions: [SessionDTO] = try await openF1.get("sessions", query: [
            URLQueryItem(name: "year", value: String(request.weekend.year)), URLQueryItem(name: "session_name", value: selected.name)])
        let matching = sessions.filter { $0.year == request.weekend.year && $0.sessionName.caseInsensitiveCompare(selected.name) == .orderedSame && $0.isCancelled != true &&
            $0.dateStart.map { abs($0.timeIntervalSince(start)) <= 12 * 3600 } == true }
        guard matching.count <= 1 else { throw APIError.invalidData("ambiguous OpenF1 session identity") }
        return matching.first?.sessionKey
    }

    private func openHistory(_ request: RaceHistoryRequest, publish: @escaping @Sendable (RaceHistory) async -> Void) async throws -> RaceHistory {
        guard let session = try await openSession(request) else { return empty(request, provider: .openF1) }
        let query = [URLQueryItem(name: "session_key", value: String(session))]
        let laps: [HistoricalLapDTO] = try await openF1.get("laps", query: query)
        guard !laps.isEmpty else { return empty(request, provider: .openF1) }
        let positions: [HistoricalPositionDTO] = try await openF1.get("position", query: query)
        let drivers: [HistoricalDriverDTO] = try await openF1.get("drivers", query: query)
        var preview = try OpenF1HistoryMapper.map(request: request, session: session, laps: laps, positions: positions,
            drivers: drivers, intervals: [], stints: nil, pits: nil, control: [], updatedAt: now())
        guard request.session?.isGrandPrix != true || !preview.needsPositionRepair else { throw APIError.invalidData("incomplete OpenF1 position history") }
        preview.detailsComplete = false
        await publish(preview)
        var limitations: [String] = []
        let stints: [HistoricalStintDTO]? = try await optional("Tyre history", issues: &limitations) { try await self.openF1.get("stints", query: query) }
        let pits: [HistoricalPitDTO]? = try await optional("Pit history", issues: &limitations) { try await self.openF1.get("pit", query: query) }
        let control: [HistoricalControlDTO]? = try await optional("Race control", issues: &limitations) { try await self.openF1.get("race_control", query: query) }
        var intervals: [HistoricalIntervalDTO] = []
        let starts = laps.compactMap(\.dateStart)
        let ends = laps.compactMap { row in row.dateStart.flatMap { date in row.lapDuration.map { date.addingTimeInterval($0) } } }
        if let start = starts.min(), let end = ends.max(), end > start, end.timeIntervalSince(start) <= 6 * 3600 {
            var cursor = start
            // Bounded ten-minute slices stay below the transport/row budget. Never
            // download high-frequency history as one unbounded response.
            for _ in 0..<36 {
                if cursor > end { break }
                let next = min(end.addingTimeInterval(1), cursor.addingTimeInterval(600))
                do {
                    let rows: [HistoricalIntervalDTO] = try await openF1.get("intervals", query: query + [
                        URLQueryItem(name: "date>", value: queryDate(cursor.addingTimeInterval(-0.001))), URLQueryItem(name: "date<", value: queryDate(next))])
                    guard rows.allSatisfy({ $0.sessionKey == session }), intervals.count + rows.count <= 200_000 else {
                        throw APIError.invalidData("invalid interval history")
                    }
                    intervals += rows
                } catch is CancellationError { throw CancellationError() }
                catch { limitations.append("Some gaps are unavailable; no gaps have been estimated."); break }
                cursor = next
            }
        }
        try Task.checkCancellation()
        var history = try OpenF1HistoryMapper.map(request: request, session: session, laps: laps, positions: positions,
            drivers: drivers, intervals: intervals, stints: stints, pits: pits, control: control ?? [], updatedAt: now())
        history.limitations = limitations
        return history
    }
    private func queryDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func optional<T: Sendable>(_ name: String, issues: inout [String], operation: () async throws -> [T]) async throws -> [T]? {
        do { return try await operation() }
        catch is CancellationError { throw CancellationError() }
        catch { issues.append("\(name) unavailable."); return nil }
    }
}
