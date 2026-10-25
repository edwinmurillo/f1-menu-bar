import XCTest
@testable import F1Core

final class JolpicaRepositoryTests: XCTestCase {
    func testCalendarWinnersSprintOrderAndPublishedStandings() async throws {
        let transport = FixtureTransport(responses: JolpicaFixtures.responses)
        let value = try await repository(transport).refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertEqual(value.provider, .jolpica)
        XCTAssertTrue(value.issues.isEmpty)
        XCTAssertEqual(value.weekends.count, 2)
        XCTAssertEqual(value.weekends[0].winner?.driverName, "Fixture Winner")
        XCTAssertNil(value.weekends[1].winner)
        XCTAssertEqual(value.weekends[1].sessions.map(\.name), ["Practice 1", "Sprint Qualifying", "Sprint", "Qualifying", "Race"])
        XCTAssertTrue(value.weekends.allSatisfy { $0.id < 0 && !$0.isCancelled })
        XCTAssertEqual(value.drivers.map(\.points), [9.5, 10.5, -2])
        XCTAssertEqual(value.drivers.map(\.position), [1, 2, nil])
        XCTAssertEqual(value.drivers.last?.positionText, "E")
        XCTAssertNil(value.drivers.last?.driverNumber)
        XCTAssertEqual(Set(value.drivers.map(\.id)).count, 3)
        XCTAssertEqual(value.constructors.first?.points, 20.5)
        XCTAssertEqual(value.driverContext?.round, 1)
        XCTAssertEqual(value.driverContext?.sessionID, value.weekends[0].grandPrix?.id)
        let requests = await transport.requests
        XCTAssertTrue(requests.contains { $0.url?.path == "/ergast/f1/2026/1/driverStandings.json" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.contains("F1MenuBar/") == true })
    }

    func testMissingTimeIsUnknownAndEndTimesAreNotInvented() async throws {
        var responses = JolpicaFixtures.responses
        responses["2026.json"] = JolpicaFixtures.schedule.replacingJSON("\"time\":\"01:30:00Z\"", with: "\"time\":null")
        let value = try await repository(FixtureTransport(responses: responses)).refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertNil(value.weekends[0].sessions.first { $0.name == "Practice 1" }?.start)
        XCTAssertTrue(value.weekends.flatMap(\.sessions).allSatisfy { $0.end == nil })
    }

    func testFailedDriverStandingsPreserveOnlyJolpicaPointsWhileConstructorsRefresh() async throws {
        let previous = try await repository(FixtureTransport(responses: JolpicaFixtures.responses)).refresh(year: 2026, previous: nil, publish: { _ in })
        var responses = JolpicaFixtures.responses
        responses["driverStandings.json"] = HTTPResponse(data: Data(), status: 403)
        let updated = try await repository(FixtureTransport(responses: responses)).refresh(year: 2026, previous: previous, publish: { _ in })
        XCTAssertEqual(updated.drivers, previous.drivers)
        XCTAssertNotNil(updated.issues[.drivers])
        XCTAssertNil(updated.issues[.constructors])
        XCTAssertEqual(updated.constructors.count, 1)
    }

    func testStandingsFromAnotherRoundAreRejected() async throws {
        var responses = JolpicaFixtures.responses
        responses["driverStandings.json"] = responses["driverStandings.json"]!.replacingJSON("\"round\":\"1\"", with: "\"round\":\"2\"")
        let value = try await repository(FixtureTransport(responses: responses)).refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertTrue(value.drivers.isEmpty)
        XCTAssertNotNil(value.issues[.drivers])
        XCTAssertFalse(value.constructors.isEmpty)
    }

    func testInvalidPaginationAndMalformedCalendarDoNotEraseCache() async throws {
        let previous = try await repository(FixtureTransport(responses: JolpicaFixtures.responses)).refresh(year: 2026, previous: nil, publish: { _ in })
        for response in [Fixtures.json("{}"), JolpicaFixtures.schedule.replacingJSON("\"total\":\"2\"", with: "\"total\":\"501\"")] {
            var responses = JolpicaFixtures.responses; responses["2026.json"] = response
            let value = try await repository(FixtureTransport(responses: responses)).refresh(year: 2026, previous: previous, publish: { _ in })
            XCTAssertEqual(value.weekends, previous.weekends)
            XCTAssertNotNil(value.issues[.schedule])
        }
    }

    func testOpenF1Global401OnFirstLaunchAutomaticallyLoadsBackup() async throws {
        let blocked = FixtureTransport(responses: ["meetings": HTTPResponse(data: Data(), status: 401)])
        let fallback = FallbackSeasonRepository(
            primary: OpenF1Repository(client: OpenF1Client(transport: blocked, requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now }),
            fallback: repository(FixtureTransport(responses: JolpicaFixtures.responses)))
        let value = try await fallback.refresh(year: 2026, previous: nil, publish: { _ in })
        XCTAssertEqual(value.provider, .jolpica)
        XCTAssertEqual(value.weekends.count, 2)
        XCTAssertFalse(value.drivers.isEmpty)
        XCTAssertFalse(value.constructors.isEmpty)
        XCTAssertTrue(value.issues.isEmpty)
        let requests = await blocked.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testOpenF1RecoveryReplacesBackupWithoutMergingIdentities() async throws {
        let previous = try await repository(FixtureTransport(responses: JolpicaFixtures.responses)).refresh(year: 2026, previous: nil, publish: { _ in })
        let backupTransport = FixtureTransport(responses: JolpicaFixtures.responses)
        let fallback = FallbackSeasonRepository(
            primary: OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(), requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now }),
            fallback: repository(backupTransport))
        let value = try await fallback.refresh(year: 2026, previous: previous, publish: { _ in })
        XCTAssertEqual(value.provider, .openF1)
        XCTAssertTrue(value.weekends.allSatisfy { $0.id > 0 })
        XCTAssertEqual(value.drivers.count, 2)
        let requests = await backupTransport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testProviderCachesAreSeparateAndBackupSurvivesBothProvidersFailing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let primaryCache = SnapshotCache(directory: root)
        let backupCache = SnapshotCache(directory: root, provider: .jolpica)
        let saved = try await repository(FixtureTransport(responses: JolpicaFixtures.responses)).refresh(year: 2026, previous: nil, publish: { _ in })
        try await backupCache.save(saved)
        let noPrimaryCache = try await primaryCache.load(year: 2026)
        XCTAssertNil(noPrimaryCache)
        do { try await primaryCache.save(saved); XCTFail("A Jolpica snapshot cannot enter the OpenF1 cache") }
        catch CacheError.incompatible { }
        let fallback = FallbackSeasonRepository(
            primary: OpenF1Repository(client: OpenF1Client(transport: FixtureTransport(responses: [:]), requestSpacing: .zero), cache: primaryCache),
            fallback: JolpicaRepository(client: JolpicaClient(transport: FixtureTransport(responses: [:]), requestSpacing: .zero), cache: backupCache))
        let cached = try await fallback.cached(year: 2026)
        XCTAssertEqual(cached, saved)
        let value = try await fallback.refresh(year: 2026, previous: saved, publish: { _ in })
        XCTAssertEqual(value.weekends, saved.weekends)
        XCTAssertEqual(value.drivers, saved.drivers)
        XCTAssertNotNil(value.issues[.schedule])
    }

    private func repository(_ transport: FixtureTransport) -> JolpicaRepository {
        JolpicaRepository(client: JolpicaClient(transport: transport, requestSpacing: .zero), cache: MemoryCache(), now: { Fixtures.now })
    }
}

private extension HTTPResponse {
    func replacingJSON(_ text: String, with replacement: String) -> HTTPResponse {
        Fixtures.json(String(decoding: data, as: UTF8.self).replacingOccurrences(of: text, with: replacement))
    }
}

private enum JolpicaFixtures {
    static let firstRace = """
    {"season":"2026","round":"1","raceName":"Coastal Grand Prix",
    "Circuit":{"circuitId":"coast","circuitName":"Coast","Location":{"locality":"Coast","country":"Country"}},
    "date":"2026-03-08","time":"04:00:00Z","FirstPractice":{"date":"2026-03-06","time":"01:30:00Z"}}
    """
    static let sprintRace = """
    {"season":"2026","round":"2","raceName":"Mountain Grand Prix",
    "Circuit":{"circuitId":"mountain","circuitName":"Mountain","Location":{"locality":"Mountain","country":"Country"}},
    "date":"2026-06-14","time":"14:00:00Z","FirstPractice":{"date":"2026-06-12","time":"11:00:00Z"},
    "SprintQualifying":{"date":"2026-06-12","time":"15:00:00Z"},"Sprint":{"date":"2026-06-13","time":"11:00:00Z"},
    "Qualifying":{"date":"2026-06-13","time":"15:00:00Z"}}
    """
    static let constructor = """
    {"constructorId":"coral","name":"Coral"}
    """
    static let driver = """
    {"driverId":"winner","permanentNumber":"9","givenName":"Fixture","familyName":"Winner"}
    """
    static let schedule = Fixtures.json("""
    {"MRData":{"total":"2","offset":"0","RaceTable":{"Races":[\(firstRace),\(sprintRace)]}}}
    """)
    static let responses: [String: HTTPResponse] = [
        "2026.json": schedule,
        "1.json": Fixtures.json("""
        {"MRData":{"total":"1","offset":"0","RaceTable":{"Races":[\(firstRace.dropLast()),
        "Results":[{"position":"1","number":"9","Driver":\(driver),"Constructor":\(constructor)}]}]}}}
        """),
        "driverStandings.json": Fixtures.json("""
        {"MRData":{"total":"3","offset":"0","StandingsTable":{"StandingsLists":[{"season":"2026","round":"1","DriverStandings":[
        {"position":"1","positionText":"1","points":"9.5","Driver":\(driver),"Constructors":[\(constructor)]},
        {"position":"2","positionText":"2","points":"10.5","Driver":{"driverId":"other","permanentNumber":"8","givenName":"Another","familyName":"Driver"},"Constructors":[\(constructor)]},
        {"positionText":"E","points":"-2","Driver":{"driverId":"excluded","givenName":"Excluded","familyName":"Driver"},"Constructors":[\(constructor)]}
        ]}]}}}
        """),
        "constructorStandings.json": Fixtures.json("""
        {"MRData":{"total":"1","offset":"0","StandingsTable":{"StandingsLists":[{"season":"2026","round":"1","ConstructorStandings":[
        {"position":"1","positionText":"1","points":"20.5","Constructor":\(constructor)}]}]}}}
        """)
    ]
}
