import Foundation

public actor JolpicaClient {
    private let http: JSONHTTPClient

    public init(transport: any HTTPTransport = URLSessionTransport(), requestSpacing: Duration = .milliseconds(2100)) {
        http = JSONHTTPClient(transport: transport, requestSpacing: requestSpacing)
    }

    func races(year: Int, winnersOnly: Bool = false) async throws -> [JolpicaRace] {
        try await rows("\(year)\(winnersOnly ? "/results/1" : "")") { page in
            guard let table = page.races else { throw APIError.invalidData("missing Jolpica calendar") }
            return table.races
        }
    }

    func drivers(year: Int, round: Int) async throws -> [JolpicaDriverStanding] {
        try await rows("\(year)/\(round)/driverStandings") { page in
            guard let table = page.standings else { throw APIError.invalidData("missing Jolpica standings") }
            return try table.lists.flatMap { list in
                guard list.season == String(year), list.round == String(round), let drivers = list.drivers else {
                    throw APIError.invalidData("Jolpica driver standings do not match the requested race")
                }
                return drivers
            }
        }
    }

    func qualifyingWinners(year: Int) async throws -> [JolpicaQualifyingEntry] {
        let entries: [JolpicaQualifyingEntry] = try await rows("\(year)/qualifying/1") { page in
            guard let table = page.races else { throw APIError.invalidData("missing Jolpica qualifying results") }
            // Pagination counts results, not race containers. This endpoint can
            // include additional classified drivers; only final position 1 is a win.
            return try table.races.flatMap { race in
                guard let results = race.qualifyingResults else { throw APIError.invalidData("missing qualifying classification") }
                return results.map { JolpicaQualifyingEntry(race: race, result: $0) }
            }
        }
        return entries.filter { $0.result.position == "1" }
    }

    func constructors(year: Int, round: Int) async throws -> [JolpicaConstructorStanding] {
        try await rows("\(year)/\(round)/constructorStandings") { page in
            guard let table = page.standings else { throw APIError.invalidData("missing Jolpica standings") }
            return try table.lists.flatMap { list in
                guard list.season == String(year), list.round == String(round), let constructors = list.constructors else {
                    throw APIError.invalidData("Jolpica constructor standings do not match the requested race")
                }
                return constructors
            }
        }
    }

    func historyPage(_ endpoint: String, offset: Int) async throws -> JolpicaHistoryPage {
        var components = URLComponents(string: "https://api.jolpi.ca/ergast/f1/\(endpoint).json")!
        components.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: String(offset))]
        guard let url = components.url else { throw APIError.invalidResponse }
        let data = try await http.get(url)
        do { return try JSONDecoder().decode(JolpicaHistoryEnvelope.self, from: data).data }
        catch { throw APIError.invalidData("unexpected Jolpica lap history format") }
    }

    private func rows<T: Sendable>(_ endpoint: String, extract: @Sendable (JolpicaPage) throws -> [T]) async throws -> [T] {
        var result: [T] = []
        var expectedTotal: Int?
        // At most five pages and 500 rows per season endpoint; never silently truncate.
        for _ in 0..<5 {
            var components = URLComponents(string: "https://api.jolpi.ca/ergast/f1/\(endpoint).json")!
            components.queryItems = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: String(result.count))]
            guard let url = components.url else { throw APIError.invalidResponse }
            let data = try await http.get(url)
            let page: JolpicaPage
            do { page = try JSONDecoder().decode(JolpicaEnvelope.self, from: data).data }
            catch { throw APIError.invalidData("unexpected Jolpica response format") }
            guard let total = Int(page.total), (0...500).contains(total), Int(page.offset) == result.count,
                  expectedTotal == nil || expectedTotal == total else {
                throw APIError.invalidData("inconsistent Jolpica pagination")
            }
            expectedTotal = total
            let batch = try extract(page)
            guard batch.count <= 100, result.count + batch.count <= total else {
                throw APIError.invalidData("inconsistent Jolpica row count")
            }
            result += batch
            if result.count == total { return result }
            guard !batch.isEmpty else { throw APIError.invalidData("incomplete Jolpica response") }
        }
        throw APIError.responseTooLarge
    }
}
