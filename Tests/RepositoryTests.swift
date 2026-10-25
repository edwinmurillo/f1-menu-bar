import XCTest
@testable import F1Core

final class RepositoryTests: XCTestCase {
    func testSprintScheduleTestingCancellationAndRaceWinner() async throws {
        let transport = FixtureTransport()
        let repository = OpenF1Repository(client: OpenF1Client(transport: transport, requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now })
        let value = try await repository.refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertEqual(value.weekends.count, 3)
        let weekend = try XCTUnwrap(value.weekends.first { $0.id == 1 })
        XCTAssertEqual(weekend.sessions.map(\.name), ["Practice 1", "Sprint Qualifying", "Sprint", "Race"])
        XCTAssertTrue(weekend.hasSprint)
        XCTAssertEqual(weekend.winner?.driverName, "Current Driver")
        XCTAssertNotEqual(weekend.winner?.driverName, "Sprint Winner")
        XCTAssertTrue(try XCTUnwrap(value.weekends.first { $0.id == 4 }).isCancelled)
        let requests = await transport.requests
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.contains("F1MenuBar/") == true })
        let standingsRequest = try XCTUnwrap(requests.first { $0.url?.lastPathComponent == "championship_drivers" })
        XCTAssertEqual(URLComponents(url: standingsRequest.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "13")
    }
    func testMissingLatestRosterUsesEarlierSeasonIdentityAndPreservesProviderPointsOrder() async throws {
        let repository = OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(), requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now })
        let value = try await repository.refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertEqual(value.drivers.map(\.driverNumber), [8, 9])
        XCTAssertEqual(value.drivers.first?.name, "Earlier Driver")
        XCTAssertEqual(value.drivers.map(\.points), [9.5, 10.5])
        XCTAssertEqual(value.constructors.first?.points, 20.5)
        XCTAssertEqual(value.driverContext?.sessionID, 13)
        XCTAssertTrue(value.issues.isEmpty)
    }
    func testFailedStandingsKeepsLastGoodPointsWhileOtherSectionsRefresh() async throws {
        let cache = MemoryCache()
        let first = OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(), requestSpacing: .zero), cache: cache, now: { Fixtures.now })
        let previous = try await first.refresh(year: 2026, previous: nil, publish: { _ in })
        var responses = Fixtures.responses
        responses["championship_drivers"] = HTTPResponse(data: Data(), status: 403)
        let second = OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(responses: responses), requestSpacing: .zero), cache: cache, now: { Fixtures.now.addingTimeInterval(100) })
        let result = try await second.refresh(year: 2026, previous: previous, publish: { _ in })
        XCTAssertEqual(result.drivers, previous.drivers)
        XCTAssertEqual(result.driverContext, previous.driverContext)
        XCTAssertNotNil(result.issues[.drivers])
        XCTAssertEqual(result.constructorContext?.updatedAt, Fixtures.now.addingTimeInterval(100))
    }
    func testMalformedCalendarPreservesCachedSchedule() async throws {
        var previous = SeasonSnapshot(year: 2026)
        previous.weekends = [RaceWeekend(id: 1, year: 2026, name: "Saved GP", sessions: [])]
        previous.scheduleUpdatedAt = Fixtures.now
        var responses = Fixtures.responses; responses["sessions"] = Fixtures.json("not json")
        let repository = OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(responses: responses), requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now })
        let result = try await repository.refresh(year: 2026, previous: previous, publish: { _ in })
        XCTAssertEqual(result.weekends, previous.weekends)
        XCTAssertNotNil(result.issues[.schedule])
    }
    func testDuplicateIdentifiersAreRejectedWithoutTrapping() throws {
        let meetings = try JSONCoding.decoder().decode([MeetingDTO].self, from: Fixtures.responses["meetings"]!.data)
        let sessions = try JSONCoding.decoder().decode([SessionDTO].self, from: Fixtures.responses["sessions"]!.data)
        XCTAssertThrowsError(try OpenF1Repository.mapSchedule(meetings: meetings + [meetings[0]], sessions: sessions, previous: [], year: 2026))
    }
    func testDisappearedRaceStaysVisibleAsUnavailable() throws {
        let previous = RaceWeekend(id: 99, year: 2026, name: "Removed GP", sessions: [])
        let mapped = try OpenF1Repository.mapSchedule(meetings: [], sessions: [], previous: [previous], year: 2026)
        XCTAssertEqual(mapped.count, 1)
        XCTAssertTrue(mapped[0].isMissingFromSchedule)
    }
    func testCacheWriteFailureIsVisibleAndDoesNotLoseOnlineData() async throws {
        let cache = MemoryCache(); await cache.failSaving()
        let repository = OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(), requestSpacing: .zero), cache: cache, now: { Fixtures.now })
        let result = try await repository.refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertFalse(result.drivers.isEmpty)
        XCTAssertTrue(result.issues[.schedule]?.contains("Offline copy") == true)
    }
}
