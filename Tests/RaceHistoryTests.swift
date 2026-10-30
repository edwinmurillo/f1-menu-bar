import XCTest
@testable import F1Core

final class RaceHistoryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private func request(provider: DataProvider = .openF1, id: Int = 1) -> RaceHistoryRequest {
        RaceHistoryRequest(weekend: RaceWeekend(id: provider == .jolpica ? -2_026_001 : id, year: 2026, name: "Test GP",
            sessions: [RaceSession(id: 10, name: "Race", start: epoch)]), provider: provider)
    }
    private func mapped(laps: [HistoricalLapDTO]? = nil, positions: [HistoricalPositionDTO]? = nil,
                        intervals: [HistoricalIntervalDTO] = []) throws -> RaceHistory {
        try OpenF1HistoryMapper.map(request: request(), session: 10, laps: laps ?? [
            HistoricalLapDTO(sessionKey: 10, driverNumber: 1, lapNumber: 1, dateStart: epoch, lapDuration: 90),
            HistoricalLapDTO(sessionKey: 10, driverNumber: 1, lapNumber: 2, dateStart: epoch.addingTimeInterval(90), lapDuration: 88),
            HistoricalLapDTO(sessionKey: 10, driverNumber: 1, lapNumber: 3, dateStart: epoch.addingTimeInterval(178), lapDuration: nil)],
            positions: positions ?? [HistoricalPositionDTO(sessionKey: 10, driverNumber: 1, date: epoch, position: 22)],
            drivers: [], intervals: intervals, stints: nil, pits: nil, control: [], updatedAt: epoch)
    }
    func testRealLapBoundariesSparseRosterAndUnfinishedLap() throws {
        let history = try mapped()
        XCTAssertEqual(history.laps.map(\.number), [1, 2])
        XCTAssertEqual(history.positionsCount, 22)
        XCTAssertEqual(history.laps[1].timings[0].position, 22)
        XCTAssertEqual(history.laps[1].timings[0].duration, 88)
        XCTAssertEqual(history.laps[1].timings[0].bestDuration, 88)
        XCTAssertNil(history.laps[1].timings[0].stops, "Failed/unavailable pit endpoint must not become zero stops")
        XCTAssertNil(history.laps[1].timings[0].gap)
        XCTAssertTrue(history.events.isEmpty)
    }
    func testNoFutureOrStaleGapSampleIsCarriedIntoLapBoundary() throws {
        let samples = [
            HistoricalIntervalDTO(sessionKey: 10, driverNumber: 1, date: epoch.addingTimeInterval(88), gapToLeader: .number(4.25)),
            HistoricalIntervalDTO(sessionKey: 10, driverNumber: 1, date: epoch.addingTimeInterval(181), gapToLeader: .number(9))]
        let history = try mapped(intervals: samples)
        XCTAssertEqual(history.laps[0].timings[0].gap, .seconds(4.25))
        XCTAssertNil(history.laps[1].timings[0].gap)
    }
    func testWrongSessionAndDuplicateLapRowsAreRejected() throws {
        let row = HistoricalLapDTO(sessionKey: 10, driverNumber: 1, lapNumber: 1, dateStart: epoch, lapDuration: 90)
        XCTAssertThrowsError(try mapped(laps: [row, row]))
        XCTAssertThrowsError(try mapped(positions: [HistoricalPositionDTO(sessionKey: 11, driverNumber: 1, date: epoch, position: 1)]))
    }
    func testGapFormatsAndInvalidLapDurationsStayUnknown() {
        XCTAssertEqual(HistoricalGapDTO.text("+2 LAPS").normalized, .laps(2))
        XCTAssertNil(HistoricalGapDTO.text("unknown").normalized)
        XCTAssertNil(HistoricalGapDTO.number(.infinity).normalized)
        XCTAssertNil(LapDuration.seconds("999999999999999999:59.999"))
        XCTAssertNil(LapDuration.seconds("1:nan"))
        XCTAssertEqual(LapDuration.seconds("1:30.125"), 90.125)
    }
    func testFallbackPagesCountTimingsAndReassembleSplitLapsWithoutInventingGaps() async throws {
        let transport = FixtureTransport(responses: [
            "sessions": HTTPResponse(data: Data(), status: 401),
            "/ergast/f1/2026/1/laps.json?limit=100&offset=0": page(total: 3, offset: 0, body: "\"Laps\":[{\"number\":\"1\",\"Timings\":[{\"driverId\":\"a\",\"position\":\"1\",\"time\":\"1:30.000\"}]}]"),
            "/ergast/f1/2026/1/laps.json?limit=100&offset=1": page(total: 3, offset: 1, body: "\"Laps\":[{\"number\":\"1\",\"Timings\":[{\"driverId\":\"b\",\"position\":\"2\",\"time\":\"1:31.000\"}]},{\"number\":\"2\",\"Timings\":[{\"driverId\":\"a\",\"position\":\"1\",\"time\":\"1:29.000\"}]}]"),
            "results.json": page(total: 0, offset: 0, body: "\"Results\":[]"),
            "pitstops.json": page(total: 0, offset: 0, body: "\"PitStops\":[]")])
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoricalRaceRepository(openF1: OpenF1Client(transport: transport, requestSpacing: .zero),
            jolpica: JolpicaClient(transport: transport, requestSpacing: .zero), cache: RaceHistoryCache(directory: directory))
        let history = try await repository.fetch(request(provider: .jolpica))
        XCTAssertEqual(history.provider, .jolpica)
        XCTAssertEqual(history.laps.map(\.number), [1, 2])
        XCTAssertEqual(history.laps[0].timings.count, 2)
        XCTAssertTrue(history.laps.flatMap(\.timings).allSatisfy { $0.gap == nil && $0.compound == nil })
        XCTAssertEqual(history.laps[1].timings[0].stops, 0, "A valid empty pit response establishes zero reported stops")
        let cached = try await repository.cached(request(provider: .jolpica))
        XCTAssertEqual(cached, history)
        let requests = await transport.requests
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.contains("F1MenuBar/") == true })
    }
    func testOpenF1GapWindowUsesDocumentedDateFilterAndRealGap() async throws {
        let transport = FixtureTransport(responses: [
            "laps": Fixtures.json("[{\"session_key\":10,\"driver_number\":1,\"lap_number\":1,\"date_start\":\"2023-11-14T22:13:20Z\",\"lap_duration\":90}]"),
            "position": Fixtures.json("[{\"session_key\":10,\"driver_number\":1,\"date\":\"2023-11-14T22:13:20Z\",\"position\":2}]"),
            "drivers": Fixtures.json("[]"), "stints": Fixtures.json("[]"), "pit": Fixtures.json("[]"), "race_control": Fixtures.json("[]"),
            "intervals": Fixtures.json("[{\"session_key\":10,\"driver_number\":1,\"date\":\"2023-11-14T22:14:48Z\",\"gap_to_leader\":4.25}]")])
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoricalRaceRepository(openF1: OpenF1Client(transport: transport, requestSpacing: .zero),
            jolpica: JolpicaClient(transport: transport, requestSpacing: .zero), cache: RaceHistoryCache(directory: directory))
        let value = try await repository.fetch(request())
        XCTAssertEqual(value.provider, .openF1)
        XCTAssertEqual(value.laps.first?.timings.first?.gap, .seconds(4.25))
        XCTAssertTrue(value.limitations.isEmpty)
        let requests = await transport.requests
        let intervals = try XCTUnwrap(requests.first { $0.url?.lastPathComponent == "intervals" }?.url)
        let query = URLComponents(url: intervals, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(query.contains { $0.name == "date>" })
        XCTAssertTrue(query.contains { $0.name == "date<" })
        XCTAssertFalse(query.contains { $0.name == "date>=" }, "The equals sign is the URL separator, not part of the API filter key")
    }

    func testWrongRoundFallbackIsRejectedInsteadOfShowingAnotherRace() async throws {
        let transport = FixtureTransport(responses: ["sessions": HTTPResponse(data: Data(), status: 401),
            "laps.json": page(total: 0, offset: 0, body: "\"Laps\":[]", round: 2)])
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = HistoricalRaceRepository(openF1: OpenF1Client(transport: transport, requestSpacing: .zero),
            jolpica: JolpicaClient(transport: transport, requestSpacing: .zero), cache: RaceHistoryCache(directory: dir))
        do { _ = try await repository.fetch(request(provider: .jolpica)); XCTFail("Wrong race must fail") } catch { }
    }
    func testCacheSeparatesRaceProviderAndSchemaAndPreservesGoodSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = RaceHistoryCache(directory: directory)
        let history = try mapped()
        try await cache.save(history)
        let loaded = try await cache.load(request())
        XCTAssertEqual(loaded, history)
        let wrong = try await cache.load(request(id: 2))
        XCTAssertNil(wrong)
        var incompatible = history; incompatible.schema = 99
        do { try await cache.save(incompatible); XCTFail("Incompatible data must not replace the good cache") } catch { }
        let empty = RaceHistory(request: request(), provider: .openF1, sourceID: "10", drivers: [], laps: [], events: [], updatedAt: epoch)
        try await cache.save(empty)
        let retained = try await cache.load(request())
        XCTAssertEqual(retained, history)
    }
    private func page(total: Int, offset: Int, body: String, round: Int = 1) -> HTTPResponse {
        Fixtures.json("{\"MRData\":{\"total\":\"\(total)\",\"offset\":\"\(offset)\",\"RaceTable\":{\"Races\":[{\"season\":\"2026\",\"round\":\"\(round)\",\(body)}]}}}")
    }
}
