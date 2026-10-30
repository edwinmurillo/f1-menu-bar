import Foundation

struct JolpicaHistoryEnvelope: Decodable { let data: JolpicaHistoryPage
    enum CodingKeys: String, CodingKey { case data = "MRData" }
}
struct JolpicaHistoryPage: Decodable, Sendable {
    let total: String
    let offset: String
    let races: RaceTable
    enum CodingKeys: String, CodingKey { case total, offset; case races = "RaceTable" }
    struct RaceTable: Decodable, Sendable {
        let races: [Race]
        enum CodingKeys: String, CodingKey { case races = "Races" }
    }
    struct Race: Decodable, Sendable {
        let season: String
        let round: String
        let laps: [Lap]?
        let results: [Result]?
        let pits: [Pit]?
        enum CodingKeys: String, CodingKey { case season, round; case laps = "Laps", results = "Results", pits = "PitStops" }
    }
    struct Lap: Decodable, Sendable {
        let number: String
        let timings: [Timing]
        enum CodingKeys: String, CodingKey { case number; case timings = "Timings" }
    }
    struct Timing: Decodable, Sendable { let driverId: String; let position: String; let time: String }
    struct Result: Decodable, Sendable {
        let driver: JolpicaDriver
        let constructor: JolpicaConstructor
        enum CodingKeys: String, CodingKey { case driver = "Driver", constructor = "Constructor" }
    }
    struct Pit: Decodable, Sendable { let driverId: String; let lap: String; let stop: String }
}

extension HistoricalRaceRepository {
    func jolpicaHistory(_ request: RaceHistoryRequest) async throws -> RaceHistory {
        let round: Int
        if request.calendarProvider == .jolpica {
            guard request.weekend.id < 0, request.weekend.id > -10_000_000 else { throw APIError.invalidData("invalid Jolpica race identity") }
            let encoded = -request.weekend.id
            guard encoded / 1000 == request.weekend.year, (1...999).contains(encoded % 1000) else {
                throw APIError.invalidData("invalid Jolpica race selection")
            }
            round = encoded % 1000
        } else {
            guard let date = request.weekend.grandPrix?.start else { return empty(request, provider: .jolpica) }
            let schedule = try await jolpica.races(year: request.weekend.year)
            let matching = try schedule.filter { race in
                guard race.season == String(request.weekend.year),
                      let timestamp = try JolpicaTime(date: race.date, time: race.time).timestamp() else { return false }
                return abs(timestamp.timeIntervalSince(date)) <= 12 * 3600
            }
            guard matching.count <= 1 else { throw APIError.invalidData("ambiguous Jolpica race identity") }
            guard let race = matching.first, let number = Int(race.round), (1...999).contains(number) else {
                return empty(request, provider: .jolpica)
            }
            round = number
        }
        let endpoint = "\(request.weekend.year)/\(round)"
        var entries: [(Int, JolpicaHistoryPage.Timing)] = []
        var total: Int?
        for _ in 0..<200 {
            let page = try await jolpica.historyPage(endpoint + "/laps", offset: entries.count)
            let expected = try validate(page, request: request, round: round, offset: entries.count, total: total, bound: 20_000)
            total = expected
            let batch = try page.races.races.flatMap { race in
                try (race.laps ?? []).flatMap { lap -> [(Int, JolpicaHistoryPage.Timing)] in
                    guard let number = Int(lap.number), (1...200).contains(number) else { throw APIError.invalidData("invalid lap number") }
                    return lap.timings.map { (number, $0) }
                }
            }
            guard batch.count <= 100, entries.count + batch.count <= expected else { throw APIError.invalidData("invalid lap pagination count") }
            entries += batch
            if entries.count == expected { break }
            guard !batch.isEmpty else { throw APIError.invalidData("incomplete lap history") }
        }
        guard entries.count == total else { throw APIError.responseTooLarge }
        guard !entries.isEmpty else { return empty(request, provider: .jolpica) }
        let resultPage = try await jolpica.historyPage(endpoint + "/results", offset: 0)
        _ = try validate(resultPage, request: request, round: round, offset: 0, total: nil, bound: 100)
        let results = resultPage.races.races.flatMap { $0.results ?? [] }
        guard results.count == Int(resultPage.total), Set(results.map { $0.driver.driverId }).count == results.count else {
            throw APIError.invalidData("incomplete driver directory")
        }
        var pits: [JolpicaHistoryPage.Pit]?
        var limitations = ["Jolpica provides lap positions and times. Gaps, tyres and race-control events are unavailable from this source."]
        do {
            let page = try await jolpica.historyPage(endpoint + "/pitstops", offset: 0)
            _ = try validate(page, request: request, round: round, offset: 0, total: nil, bound: 100)
            let rows = page.races.races.flatMap { $0.pits ?? [] }
            guard rows.count == Int(page.total), rows.allSatisfy({ row in
                Int(row.lap).map { (1...200).contains($0) } == true && Int(row.stop).map { (1...100).contains($0) } == true
            }) else { throw APIError.invalidData("incomplete pit history") }
            pits = rows
        } catch is CancellationError { throw CancellationError() }
        catch { limitations.append("Pit history unavailable.") }
        let value = try JolpicaHistoryMapper.map(request: request, round: round, entries: entries, results: results,
                                               pits: pits, date: timestamp())
        var history = value; history.limitations = limitations
        return history
    }

    private func validate(_ page: JolpicaHistoryPage, request: RaceHistoryRequest, round: Int,
                          offset: Int, total: Int?, bound: Int) throws -> Int {
        guard let count = Int(page.total), (0...bound).contains(count), Int(page.offset) == offset,
              total == nil || total == count, page.races.races.count <= 1,
              page.races.races.allSatisfy({ $0.season == String(request.weekend.year) && $0.round == String(round) }) else {
            throw APIError.invalidData("inconsistent Jolpica history identity or pagination")
        }
        return count
    }
}

enum JolpicaHistoryMapper {
    static func map(request: RaceHistoryRequest, round: Int, entries: [(Int, JolpicaHistoryPage.Timing)],
                    results: [JolpicaHistoryPage.Result], pits: [JolpicaHistoryPage.Pit]?, date: Date) throws -> RaceHistory {
        guard Set(entries.map { "\($0.0)-\($0.1.driverId)" }).count == entries.count,
              entries.allSatisfy({ !$0.1.driverId.isEmpty && Int($0.1.position).map { (1...100).contains($0) } == true && LapDuration.seconds($0.1.time) != nil }) else {
            throw APIError.invalidData("invalid Jolpica lap timing")
        }
        let ids = Set(entries.map { $0.1.driverId }).union(results.map { $0.driver.driverId }).sorted()
        guard ids.count <= 100 else { throw APIError.responseTooLarge }
        let roster = ids.map { id in
            let result = results.first { $0.driver.driverId == id }
            return RaceHistoryDriver(id: id, name: result.map { "\($0.driver.givenName) \($0.driver.familyName)" } ?? id,
                abbreviation: result?.driver.code ?? id, team: result?.constructor.name ?? "", teamColor: nil)
        }
        var best: [String: Double] = [:]
        let grouped = Dictionary(grouping: entries, by: { $0.0 })
        let laps = grouped.keys.sorted().map { number in
            RaceHistoryLap(number: number, timings: (grouped[number] ?? []).sorted { $0.1.driverId < $1.1.driverId }.map { _, timing in
                let duration = LapDuration.seconds(timing.time)!
                best[timing.driverId] = min(best[timing.driverId] ?? .infinity, duration)
                return RaceHistoryTiming(driverID: timing.driverId, position: Int(timing.position), duration: duration,
                    bestDuration: best[timing.driverId], gap: nil, compound: nil, tyreAge: nil,
                    stops: pits.map { $0.filter { $0.driverId == timing.driverId && (Int($0.lap) ?? .max) <= number }.count })
            })
        }
        return RaceHistory(request: request, provider: .jolpica, sourceID: "\(request.weekend.year)-\(round)",
                           drivers: roster, laps: laps, events: [], updatedAt: date)
    }
}
