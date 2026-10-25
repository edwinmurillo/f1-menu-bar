import Foundation

public protocol SeasonRepository: Sendable {
    func cached(year: Int) async throws -> SeasonSnapshot?
    func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot
}

public actor OpenF1Repository: SeasonRepository {
    private let client: OpenF1Client
    private let cache: any SeasonCaching
    private let now: @Sendable () -> Date

    public init(client: OpenF1Client, cache: any SeasonCaching, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.cache = cache; self.now = now
    }

    public func cached(year: Int) async throws -> SeasonSnapshot? { try await cache.load(year: year) }

    public func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        var value = previous?.year == year ? previous! : SeasonSnapshot(year: year)
        value.issues = [:]
        do {
            let query = [URLQueryItem(name: "year", value: String(year))]
            let meetings: [MeetingDTO] = try await client.get("meetings", query: query)
            let sessions: [SessionDTO] = try await client.get("sessions", query: query)
            try Task.checkCancellation()
            value.weekends = try Self.mapSchedule(meetings: meetings, sessions: sessions, previous: value.weekends, year: year)
            value.scheduleUpdatedAt = now()
        } catch is CancellationError { throw CancellationError() }
        catch { value.issues[.schedule] = error.localizedDescription }
        value = try await publishAndSave(value, publish: publish)

        // Future-only calendars need no results or championship requests.
        guard value.weekends.contains(where: { ($0.grandPrix?.start ?? .distantFuture) <= now() && !$0.isCancelled }) else { return value }

        let allSessions = value.weekends.flatMap(\.sessions)
        guard let minimum = allSessions.map(\.id).min(), let maximum = allSessions.map(\.id).max() else { return value }
        let range = [URLQueryItem(name: "session_key>", value: String(minimum - 1)), URLQueryItem(name: "session_key<", value: String(maximum + 1))]
        let knownIDs = Set(allSessions.map(\.id))
        var directory: [DriverDTO] = []
        var metadataError: String?
        do {
            let entries: [DriverDTO] = try await client.get("drivers", query: range)
            directory = entries.filter { knownIDs.contains($0.sessionKey) }
        } catch is CancellationError { throw CancellationError() }
        catch { metadataError = error.localizedDescription }

        do {
            let results: [ResultDTO] = try await client.get("session_result", query: range + [URLQueryItem(name: "position", value: "1")])
            try Task.checkCancellation()
            for index in value.weekends.indices {
                let weekend = value.weekends[index]
                guard !weekend.isCancelled, let race = weekend.grandPrix,
                      (race.start ?? .distantFuture) <= now(),
                      let result = results.last(where: { $0.sessionKey == race.id && $0.position == 1 }) else { continue }
                let driver = Self.driver(result.driverNumber, at: race, directory: directory, sessions: allSessions)
                // Preserve resolved metadata if a metadata request fails during a refresh.
                let old = weekend.winner?.driverNumber == result.driverNumber ? weekend.winner : nil
                value.weekends[index].winner = RaceWinner(driverNumber: result.driverNumber,
                    driverName: driver?.name ?? old?.driverName ?? "Driver \(result.driverNumber)",
                    team: driver?.teamName ?? old?.team ?? "Team unavailable")
            }
            value.resultsUpdatedAt = now()
            if let metadataError { value.issues[.results] = "Driver names could not be refreshed. \(metadataError)" }
        } catch is CancellationError { throw CancellationError() }
        catch { value.issues[.results] = error.localizedDescription }
        value = try await publishAndSave(value, publish: publish)

        let completed = value.weekends.filter { $0.winner != nil && !$0.isCancelled && !$0.isMissingFromSchedule }
            .sorted { $0.sortDate > $1.sortDate }.prefix(3)
        for section in [DataSection.drivers, .constructors] {
            do {
                var found = false
                for weekend in completed {
                    guard let race = weekend.grandPrix else { continue }
                    let query = [URLQueryItem(name: "session_key", value: String(race.id))]
                    if section == .drivers {
                        let rows: [DriverChampionshipDTO] = try await client.get("championship_drivers", query: query)
                        if rows.isEmpty { continue }
                        try Self.validateStandings(rows.map { ($0.driverNumber.description, $0.sessionKey, $0.positionCurrent, $0.pointsCurrent) }, session: race.id)
                        value.drivers = rows.map { row in
                            let person = Self.driver(row.driverNumber, at: race, directory: directory, sessions: allSessions)
                            let old = value.drivers.first { $0.driverNumber == row.driverNumber }
                            return DriverStanding(driverNumber: row.driverNumber, position: row.positionCurrent,
                                name: person?.name ?? old?.name ?? "Driver \(row.driverNumber)",
                                team: person?.teamName ?? old?.team ?? "Team unavailable", teamColor: person?.teamColour ?? old?.teamColor, points: row.pointsCurrent)
                        }.sorted { $0.position == $1.position ? $0.driverNumber < $1.driverNumber : $0.position < $1.position }
                        value.driverContext = ChampionshipContext(sessionID: race.id, meetingName: weekend.name, updatedAt: now())
                    } else {
                        let rows: [TeamChampionshipDTO] = try await client.get("championship_teams", query: query)
                        if rows.isEmpty { continue }
                        try Self.validateStandings(rows.map { ($0.teamName, $0.sessionKey, $0.positionCurrent, $0.pointsCurrent) }, session: race.id)
                        value.constructors = rows.map { row in
                            let roster = directory.filter { $0.sessionKey == race.id && $0.teamName == row.teamName }
                            let names = Set(roster.map { $0.lastName ?? $0.name }).sorted().joined(separator: " · ")
                            let old = value.constructors.first { $0.name == row.teamName }
                            return ConstructorStanding(name: row.teamName, position: row.positionCurrent,
                                drivers: names.isEmpty ? old?.drivers ?? "" : names,
                                color: roster.first?.teamColour ?? old?.color, points: row.pointsCurrent)
                        }.sorted { $0.position == $1.position ? $0.name < $1.name : $0.position < $1.position }
                        value.constructorContext = ChampionshipContext(sessionID: race.id, meetingName: weekend.name, updatedAt: now())
                    }
                    found = true
                    if let metadataError { value.issues[section] = "Some names may be unavailable. \(metadataError)" }
                    break
                }
                if !found, !completed.isEmpty { value.issues[section] = "Championship points have not been published for the latest races yet." }
            } catch is CancellationError { throw CancellationError() }
            catch { value.issues[section] = error.localizedDescription }
            value = try await publishAndSave(value, publish: publish)
        }
        return value
    }

    private func publishAndSave(_ value: SeasonSnapshot, publish: @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        try Task.checkCancellation()
        await publish(value)
        if value.latestUpdate != nil {
            try Task.checkCancellation()
            do { try await cache.save(value) }
            catch is CancellationError { throw CancellationError() }
            catch {
                var warned = value
                let existing = warned.issues[.schedule].map { $0 + " " } ?? ""
                warned.issues[.schedule] = existing + "Offline copy could not be saved: \(error.localizedDescription)"
                await publish(warned)
                return warned
            }
        }
        return value
    }

    static func mapSchedule(meetings: [MeetingDTO], sessions: [SessionDTO], previous: [RaceWeekend], year: Int) throws -> [RaceWeekend] {
        let meetings = meetings.filter { $0.year == year }
        let sessions = sessions.filter { $0.year == year }
        guard Set(meetings.map(\.meetingKey)).count == meetings.count,
              Set(sessions.map(\.sessionKey)).count == sessions.count,
              meetings.allSatisfy({ $0.meetingKey > 0 }), sessions.allSatisfy({ $0.sessionKey > 0 && $0.sessionKey < Int.max }) else {
            throw APIError.invalidData("duplicate or invalid calendar identifiers")
        }
        var mapped = meetings.compactMap { meeting -> RaceWeekend? in
            let entries = sessions.filter { $0.meetingKey == meeting.meetingKey }
            guard entries.contains(where: { $0.sessionName == "Race" }) || meeting.meetingName.localizedCaseInsensitiveContains("Grand Prix") else { return nil }
            let sorted = entries.map { RaceSession(id: $0.sessionKey, name: $0.sessionName, start: $0.dateStart, end: $0.dateEnd, isCancelled: $0.isCancelled ?? false) }
                .sorted { ($0.start ?? .distantFuture, $0.id) < ($1.start ?? .distantFuture, $1.id) }
            let old = previous.first { $0.id == meeting.meetingKey }
            let race = sorted.first(where: \.isGrandPrix)
            return RaceWeekend(id: meeting.meetingKey, year: year, name: meeting.meetingName,
                circuit: meeting.circuitShortName ?? "Circuit to be announced", country: meeting.countryName ?? "",
                location: meeting.location ?? "", start: meeting.dateStart, sessions: sorted,
                isCancelled: (meeting.isCancelled ?? false) || (race?.isCancelled ?? false),
                winner: old?.grandPrix?.id == race?.id ? old?.winner : nil)
        }
        let ids = Set(mapped.map(\.id))
        mapped += previous.filter { !ids.contains($0.id) }.map { old in
            var removed = old; removed.isMissingFromSchedule = true; return removed
        }
        return mapped.sorted { ($0.sortDate, $0.id) < ($1.sortDate, $1.id) }
    }

    static func driver(_ number: Int, at race: RaceSession, directory: [DriverDTO], sessions: [RaceSession]) -> DriverDTO? {
        if let exact = directory.last(where: { $0.driverNumber == number && $0.sessionKey == race.id }) { return exact }
        let dates = sessions.reduce(into: [Int: Date]()) { if let date = $1.start { $0[$1.id] = date } }
        return directory.filter { $0.driverNumber == number && (dates[$0.sessionKey] ?? .distantFuture) <= (race.start ?? .distantPast) }
            .max { (dates[$0.sessionKey] ?? .distantPast) < (dates[$1.sessionKey] ?? .distantPast) }
    }

    private static func validateStandings(_ rows: [(String, Int, Int, Double)], session: Int) throws {
        guard Set(rows.map(\.0)).count == rows.count,
              rows.allSatisfy({ !$0.0.isEmpty && $0.1 == session && $0.2 > 0 && $0.3.isFinite }) else {
            throw APIError.invalidData("inconsistent championship snapshot")
        }
    }
}
