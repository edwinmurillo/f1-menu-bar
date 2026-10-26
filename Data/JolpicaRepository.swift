import Foundation

public actor JolpicaRepository: SeasonRepository {
    private let client: JolpicaClient
    private let cache: any SeasonCaching
    private let now: @Sendable () -> Date

    public init(client: JolpicaClient, cache: any SeasonCaching, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.cache = cache; self.now = now
    }

    public func cached(year: Int) async throws -> SeasonSnapshot? { try await cache.load(year: year) }

    public func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        var value = previous?.year == year && previous?.provider == .jolpica ? previous! : SeasonSnapshot(year: year, provider: .jolpica)
        value.issues = [:]
        do {
            let races = try await client.races(year: year)
            value.weekends = try Self.mapSchedule(races, previous: value.weekends, year: year)
            value.scheduleUpdatedAt = now()
        } catch is CancellationError { throw CancellationError() }
        catch {
            value.issues[.schedule] = error.localizedDescription
            return try await publishAndSave(value, publish: publish)
        }
        value = try await publishAndSave(value, publish: publish)
        guard value.weekends.contains(where: { weekend in
            weekend.activeSessions.contains { ($0.isGrandPrix || $0.isQualifying) && ($0.start ?? .distantFuture) <= now() }
        }) else { return value }

        do {
            let races = try await client.races(year: year, winnersOnly: true)
            var winners: [Int: RaceWinner] = [:]
            for race in races {
                let id = try Self.eventID(year: year, race: race)
                guard winners[id] == nil, let result = race.results?.first, race.results?.count == 1, result.position == "1" else {
                    throw APIError.invalidData("invalid Jolpica Grand Prix winner")
                }
                guard let weekend = value.weekends.first(where: { $0.id == id }),
                      weekend.name == race.raceName, weekend.circuit == race.circuit.circuitName,
                      (weekend.grandPrix?.start ?? .distantPast) <= now() else { continue }
                winners[id] = RaceWinner(driverNumber: Int(result.number ?? result.driver.permanentNumber ?? ""),
                    driverName: result.driver.name, team: result.constructor.name,
                    driverID: result.driver.driverId, constructorID: result.constructor.constructorId)
            }
            for index in value.weekends.indices {
                if let winner = winners[value.weekends[index].id] { value.weekends[index].winner = winner }
            }
            value.resultsUpdatedAt = now()
        } catch is CancellationError { throw CancellationError() }
        catch { value.issues[.results] = error.localizedDescription }
        value = try await publishAndSave(value, publish: publish)

        do {
            let entries = try await client.qualifyingWinners(year: year)
            var winners: [Int: RaceWinner] = [:]
            for entry in entries {
                let id = try Self.eventID(year: year, race: entry.race)
                guard winners[id] == nil else { throw APIError.invalidData("duplicate Jolpica qualifying winner") }
                guard let weekend = value.weekends.first(where: { $0.id == id }),
                      !weekend.isMissingFromSchedule, !weekend.isCancelled,
                      weekend.name == entry.race.raceName, weekend.circuit == entry.race.circuit.circuitName,
                      (weekend.sessions.first(where: \.isQualifying)?.start ?? .distantPast) <= now() else { continue }
                let result = entry.result
                winners[id] = RaceWinner(driverNumber: Int(result.number ?? result.driver.permanentNumber ?? ""),
                    driverName: result.driver.name, team: result.constructor.name,
                    driverID: result.driver.driverId, constructorID: result.constructor.constructorId)
            }
            for index in value.weekends.indices {
                if let winner = winners[value.weekends[index].id] { value.weekends[index].qualifyingWinner = winner }
            }
            value.qualifyingUpdatedAt = now()
        } catch is CancellationError { throw CancellationError() }
        catch { value.issues[.qualifying] = error.localizedDescription }
        value = try await publishAndSave(value, publish: publish)

        let completed = value.weekends.filter { $0.winner != nil && !$0.isMissingFromSchedule }
            .sorted { $0.sortDate > $1.sortDate }.prefix(3)
        for section in [DataSection.drivers, .constructors] {
            do {
                var found = false
                for weekend in completed {
                    let round = (-weekend.id) % 1000
                    guard let race = weekend.grandPrix else { continue }
                    let context = ChampionshipContext(sessionID: race.id, meetingName: weekend.name, updatedAt: now(), round: round)
                    if section == .drivers {
                        let rows = try await client.drivers(year: year, round: round)
                        if rows.isEmpty { continue }
                        guard Set(rows.map { $0.driver.driverId }).count == rows.count else { throw APIError.invalidData("duplicate Jolpica drivers") }
                        value.drivers = try rows.map { row in
                            DriverStanding(driverID: row.driver.driverId, driverNumber: Int(row.driver.permanentNumber ?? ""),
                                position: try Self.position(row.position, text: row.positionText), positionText: row.positionText,
                                name: row.driver.name, team: row.constructors.map(\.name).joined(separator: " / "),
                                teamColor: nil, points: try Self.points(row.points))
                        }
                        value.driverContext = context
                    } else {
                        let rows = try await client.constructors(year: year, round: round)
                        if rows.isEmpty { continue }
                        guard Set(rows.map { $0.constructor.constructorId }).count == rows.count,
                              rows.allSatisfy({ !$0.constructor.constructorId.isEmpty }) else { throw APIError.invalidData("invalid Jolpica constructor identities") }
                        value.constructors = try rows.map { row in
                            ConstructorStanding(constructorID: row.constructor.constructorId, name: row.constructor.name, position: try Self.position(row.position, text: row.positionText),
                                positionText: row.positionText, drivers: "", color: nil, points: try Self.points(row.points))
                        }
                        value.constructorContext = context
                    }
                    found = true
                    break
                }
                if !found, !completed.isEmpty { value.issues[section] = "Championship points have not been published for the latest races yet." }
            } catch is CancellationError { throw CancellationError() }
            catch { value.issues[section] = error.localizedDescription }
            value = try await publishAndSave(value, publish: publish)
        }
        return value
    }

    static func mapSchedule(_ races: [JolpicaRace], previous: [RaceWeekend], year: Int) throws -> [RaceWeekend] {
        var mapped = try races.map { race in
            let id = try eventID(year: year, race: race)
            let times: [(String, JolpicaTime?)] = [
                ("Practice 1", race.firstPractice), ("Practice 2", race.secondPractice), ("Practice 3", race.thirdPractice),
                ("Sprint Qualifying", race.sprintQualifying ?? race.sprintShootout), ("Sprint", race.sprint),
                ("Qualifying", race.qualifying), ("Race", JolpicaTime(date: race.date, time: race.time))
            ]
            let sessions = try times.enumerated().compactMap { index, entry -> RaceSession? in
                guard let time = entry.1 else { return nil }
                return RaceSession(id: id * 10 - index, name: entry.0, start: try time.timestamp())
            }.sorted { ($0.start ?? .distantFuture, -$0.id) < ($1.start ?? .distantFuture, -$1.id) }
            let old = previous.first { $0.id == id && $0.name == race.raceName && $0.circuit == race.circuit.circuitName }
            return RaceWeekend(id: id, year: year, name: race.raceName, circuit: race.circuit.circuitName,
                country: race.circuit.location.country, location: race.circuit.location.locality,
                sessions: sessions, winner: old?.winner, qualifyingWinner: old?.qualifyingWinner)
        }
        let ids = Set(mapped.map(\.id))
        guard ids.count == mapped.count else { throw APIError.invalidData("duplicate Jolpica races") }
        mapped += previous.filter { !ids.contains($0.id) }.map { old in
            var removed = old; removed.isMissingFromSchedule = true; return removed
        }
        return mapped.sorted { ($0.sortDate, -$0.id) < ($1.sortDate, -$1.id) }
    }

    private static func eventID(year: Int, race: JolpicaRace) throws -> Int {
        guard (1900...9999).contains(year), race.season == String(year), let round = Int(race.round), (1...999).contains(round) else {
            throw APIError.invalidData("invalid Jolpica season or round")
        }
        // A separate ID namespace prevents collisions with OpenF1 meeting/session keys.
        return -(year * 1000 + round)
    }
    private static func points(_ string: String) throws -> Double {
        guard let value = Double(string), value.isFinite else { throw APIError.invalidData("invalid championship points") }
        return value
    }
    private static func position(_ string: String?, text: String) throws -> Int? {
        guard let string else {
            guard !text.isEmpty else { throw APIError.invalidData("missing championship classification") }
            return nil
        }
        guard let value = Int(string), value > 0 else { throw APIError.invalidData("invalid championship position") }
        return value
    }

    private func publishAndSave(_ value: SeasonSnapshot, publish: @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        try Task.checkCancellation()
        await publish(value)
        if value.latestUpdate != nil {
            do { try await cache.save(value) }
            catch is CancellationError { throw CancellationError() }
            catch {
                var warned = value
                warned.issues[.schedule] = [warned.issues[.schedule], "Offline copy could not be saved: \(error.localizedDescription)"].compactMap { $0 }.joined(separator: " ")
                await publish(warned)
                return warned
            }
        }
        return value
    }
}
