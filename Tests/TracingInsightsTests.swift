import XCTest
@testable import F1Core

final class TracingInsightsTests: XCTestCase {
    func testPublishedRaceIntegrationWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["F1_TRACK_MAP_INTEGRATION"] == "1" else {
            throw XCTSkip("Set F1_TRACK_MAP_INTEGRATION=1 for the public source check")
        }
        let replay = try await TracingInsightsRepository().load(year: 2026,
            weekend: "United States Grand Prix", session: "Race")
        XCTAssertGreaterThanOrEqual(replay.cars.count, 15)
        XCTAssertGreaterThan(replay.outline.count, 40)
        XCTAssertFalse(replay.isPreview)
    }

    func testRecordedLapFilesUseOneSessionClockAndRealCoordinates() async throws {
        let times = (0..<200).map { Double($0) / 2 }
        func telemetry(_ shift: Double) throws -> HTTPResponse {
            let data = try JSONSerialization.data(withJSONObject: ["tel": [
                "time": times,
                "x": times.map { 1000 + 300 * cos($0 / 100 * 2 * .pi) + shift },
                "y": times.map { 1000 + 200 * sin($0 / 100 * 2 * .pi) }
            ]])
            return HTTPResponse(data: data, status: 200)
        }
        let prefix = "/TracingInsights/2026/main/Test Grand Prix/Race"
        let transport = FixtureTransport(responses: [
            "\(prefix)/session_laptimes.json": Fixtures.json("""
            {"lap":[3,3],"drv":["AAA","BBB"],"lST":[100,101],"time":[90,90]}
            """),
            "\(prefix)/drivers.json": Fixtures.json("""
            {"drivers":[{"driver":"AAA","dn":"1","fn":"First","ln":"Driver","tc":"FF0000"},
                        {"driver":"BBB","dn":"2","fn":"Second","ln":"Driver","tc":"0000FF"}]}
            """),
            "\(prefix)/AAA/3_tel.json": try telemetry(0),
            "\(prefix)/BBB/3_tel.json": try telemetry(30)
        ])
        let replay = try await TracingInsightsRepository(transport: transport).load(year: 2026,
                                                                                    weekend: "Test Grand Prix", session: "Race")
        XCTAssertFalse(replay.isPreview)
        XCTAssertEqual(replay.sourceName, "TracingInsights / FastF1")
        XCTAssertEqual(replay.cars.count, 2)
        XCTAssertEqual(replay.duration, 89, accuracy: 0.001)
        XCTAssertGreaterThan(replay.outline.count, 40)
        XCTAssertNotNil(replay.cars[0].position(at: 40))
        XCTAssertNotNil(replay.cars[1].position(at: 40))
        XCTAssertNotEqual(replay.cars[0].position(at: 40)?.x, replay.cars[1].position(at: 40)?.x)
    }

    func testUnavailablePublishedSessionDoesNotInventMeasuredPositions() async {
        let transport = FixtureTransport(responses: ["session_laptimes.json": HTTPResponse(data: Data(), status: 404)])
        do {
            _ = try await TracingInsightsRepository(transport: transport).load(year: 2026,
                                                                                 weekend: "Missing Grand Prix", session: "Race")
            XCTFail("Expected unavailable recorded data")
        } catch {
            XCTAssertEqual(error as? APIError, .http(404))
        }
    }
}
