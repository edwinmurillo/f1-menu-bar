import Foundation
@testable import F1Core

actor FixtureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [String: HTTPResponse]
    init(responses: [String: HTTPResponse] = Fixtures.responses) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let url = request.url!
        return responses[url.path + (url.query.map { "?" + $0 } ?? "")]
            ?? responses[url.path] ?? responses[url.lastPathComponent] ?? HTTPResponse(data: Data(), status: 404)
    }
}

actor MemoryCache: SeasonCaching {
    var values: [Int: SeasonSnapshot] = [:]
    var shouldFailSaving = false
    func load(year: Int) -> SeasonSnapshot? { values[year] }
    func save(_ snapshot: SeasonSnapshot) throws {
        if shouldFailSaving { throw CacheError.incompatible }
        values[snapshot.year] = snapshot
    }
    func failSaving() { shouldFailSaving = true }
}

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_780_000_000)
    static func json(_ text: String) -> HTTPResponse { HTTPResponse(data: Data(text.utf8), status: 200) }
    static let responses: [String: HTTPResponse] = [
        "meetings": json("""
        [{"meeting_key":1,"meeting_name":"Coastal Grand Prix","circuit_short_name":"Coast","country_name":"Country","year":2026,"date_start":"2026-03-20T12:00:00Z"},
         {"meeting_key":2,"meeting_name":"Mountain Grand Prix","year":2026,"date_start":"2026-03-06T12:00:00+00:00"},
         {"meeting_key":3,"meeting_name":"Pre-Season Testing","year":2026},
         {"meeting_key":4,"meeting_name":"Cancelled Grand Prix","year":2026,"is_cancelled":true}]
        """),
        "sessions": json("""
        [{"session_key":10,"meeting_key":1,"session_name":"Practice 1","date_start":"2026-03-20T12:00:00.000+00:00","year":2026},
         {"session_key":11,"meeting_key":1,"session_name":"Sprint","date_start":"2026-03-21T12:00:00Z","year":2026},
         {"session_key":12,"meeting_key":1,"session_name":"Sprint Qualifying","date_start":"2026-03-20T16:00:00Z","year":2026},
         {"session_key":13,"meeting_key":1,"session_name":"Race","date_start":"2026-03-22T14:00:00Z","year":2026},
         {"session_key":3,"meeting_key":2,"session_name":"Race","date_start":"2026-03-08T14:00:00Z","year":2026},
         {"session_key":40,"meeting_key":3,"session_name":"Day 1","date_start":"2026-02-01T14:00:00Z","year":2026},
         {"session_key":50,"meeting_key":4,"session_name":"Race","date_start":"2026-03-01T14:00:00Z","year":2026,"is_cancelled":true}]
        """),
        "drivers": json("""
        [{"driver_number":9,"session_key":13,"first_name":"Current","last_name":"Driver","team_name":"Coral","team_colour":"FF4400"},
         {"driver_number":8,"session_key":3,"first_name":"Earlier","last_name":"Driver","team_name":"Indigo","team_colour":"1144FF"},
         {"driver_number":3,"session_key":11,"first_name":"Sprint","last_name":"Winner","team_name":"Indigo"},
         {"driver_number":8,"session_key":9999,"first_name":"Wrong","last_name":"Season","team_name":"Wrong"}]
        """),
        "session_result": json("""
        [{"session_key":13,"position":1,"driver_number":9},{"session_key":11,"position":1,"driver_number":3}]
        """),
        "championship_drivers": json("""
        [{"session_key":13,"driver_number":9,"position_current":2,"points_current":10.5},
         {"session_key":13,"driver_number":8,"position_current":1,"points_current":9.5}]
        """),
        "championship_teams": json("""
        [{"session_key":13,"team_name":"Coral","position_current":1,"points_current":20.5}]
        """)
    ]
}
