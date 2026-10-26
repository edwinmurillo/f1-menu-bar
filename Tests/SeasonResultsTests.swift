import XCTest
@testable import F1Core

final class SeasonResultsTests: XCTestCase {
    func testOpenF1UsesQualifyingClassificationAndExcludesSprintFutureAndCancelledSessions() async throws {
        let result = try await repository().refresh(year: 2026, previous: nil, publish: { _ in })
        let weekend = try XCTUnwrap(result.weekends.first { $0.id == 1 })
        XCTAssertEqual(weekend.qualifyingWinner?.driverNumber, 9)
        XCTAssertEqual(weekend.qualifyingWinner?.team, "Previous Team")
        XCTAssertEqual(weekend.winner?.team, "Coral")
        XCTAssertNil(result.weekends.first { $0.id == 2 }?.qualifyingWinner)
        XCTAssertNil(result.weekends.first { $0.id == 4 }?.qualifyingWinner)
        let driver = try XCTUnwrap(result.drivers.first { $0.driverNumber == 9 })
        let wins = SeasonStatistics.victories(for: driver, in: result)
        XCTAssertEqual(wins.count, 1)
        XCTAssertTrue(wins[0].qualifying && wins[0].grandPrix)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testOpenF1QualifyingLoadsBeforeTheRaceWithoutInventingPointsOrAWinner() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-21T18:00:00Z"))
        let transport = FixtureTransport(responses: try qualifyingResponses())
        let repository = OpenF1Repository(client: OpenF1Client(transport: transport, requestSpacing: .zero), cache: MemoryCache(), now: { now })
        let result = try await repository.refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertNotNil(result.weekends.first { $0.id == 1 }?.qualifyingWinner)
        XCTAssertTrue(result.weekends.allSatisfy { $0.winner == nil })
        XCTAssertTrue(result.drivers.isEmpty)
        XCTAssertNil(result.driverContext)
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { $0.url?.lastPathComponent.hasPrefix("championship_") == true })
    }

    func testOpenF1ResultFailurePreservesBothTypesOfCachedWin() async throws {
        let previous = try await repository().refresh(year: 2026, previous: nil, publish: { _ in })
        var responses = try qualifyingResponses()
        responses["session_result"] = HTTPResponse(data: Data(), status: 403)
        let repository = OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(responses: responses), requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now })
        let result = try await repository.refresh(year: 2026, previous: previous, publish: { _ in })
        XCTAssertEqual(result.weekends, previous.weekends)
        XCTAssertEqual(result.qualifyingUpdatedAt, previous.qualifyingUpdatedAt)
        XCTAssertNotNil(result.issues[.results])
        XCTAssertNotNil(result.issues[.qualifying])
        XCTAssertEqual(result.drivers, previous.drivers)
    }

    private func repository() throws -> OpenF1Repository {
        OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(responses: try qualifyingResponses()), requestSpacing: .zero),
            cache: MemoryCache(), now: { Fixtures.now })
    }

    private func qualifyingResponses() throws -> [String: HTTPResponse] {
        var responses = Fixtures.responses
        responses["sessions"] = try appending(responses["sessions"]!, rows: """
        [{"session_key":14,"meeting_key":1,"session_name":"Qualifying","date_start":"2026-03-21T16:00:00Z","year":2026},
         {"session_key":31,"meeting_key":2,"session_name":"Qualifying","date_start":"2026-12-20T16:00:00Z","year":2026},
         {"session_key":51,"meeting_key":4,"session_name":"Qualifying","date_start":"2026-02-28T16:00:00Z","year":2026,"is_cancelled":true}]
        """)
        responses["session_result"] = try appending(responses["session_result"]!, rows: """
        [{"session_key":14,"position":1,"driver_number":9},
         {"session_key":12,"position":1,"driver_number":8},
         {"session_key":31,"position":1,"driver_number":8},
         {"session_key":51,"position":1,"driver_number":8},
         {"session_key":9999,"position":1,"driver_number":8}]
        """)
        responses["drivers"] = try appending(responses["drivers"]!, rows: """
        [{"driver_number":9,"session_key":14,"first_name":"Current","last_name":"Driver","team_name":"Previous Team"}]
        """)
        return responses
    }

    private func appending(_ response: HTTPResponse, rows: String) throws -> HTTPResponse {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [[String: Any]])
        let added = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rows.utf8)) as? [[String: Any]])
        return HTTPResponse(data: try JSONSerialization.data(withJSONObject: original + added), status: 200)
    }
}
