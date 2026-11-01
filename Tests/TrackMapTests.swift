import XCTest
@testable import F1Core

final class TrackMapTests: XCTestCase {
    func testLocationSamplesTraceALapAndInterpolateCars() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = (1...2).flatMap { driver in
            (0..<90).map { second in
                let angle = Double(second) / 90 * 2 * Double.pi
                return """
                {"session_key":10,"driver_number":\(driver),"date":"\(formatter.string(from: start.addingTimeInterval(Double(second))))","x":\(1000 + Int(cos(angle) * 300) + driver * 10),"y":\(1000 + Int(sin(angle) * 200))}
                """
            }
        }
        let transport = FixtureTransport(responses: [
            "laps": Fixtures.json("[{\"session_key\":10,\"driver_number\":1,\"lap_number\":3,\"date_start\":\"\(formatter.string(from: start))\",\"lap_duration\":90}]"),
            "location": Fixtures.json("[\(rows.joined(separator: ","))]"),
            "drivers": Fixtures.json("[{\"session_key\":10,\"driver_number\":1,\"full_name\":\"Test One\",\"name_acronym\":\"ONE\",\"team_colour\":\"FF0000\"},{\"session_key\":10,\"driver_number\":2,\"full_name\":\"Test Two\",\"name_acronym\":\"TWO\"}]")
        ])
        let replay = try await TrackMapRepository(client: OpenF1Client(transport: transport, requestSpacing: .zero)).load(sessionID: 10)
        XCTAssertFalse(replay.isPreview)
        XCTAssertEqual(replay.cars.count, 2)
        XCTAssertEqual(replay.outline.count, 45)
        XCTAssertEqual(try XCTUnwrap(replay.cars[0].position(at: 0.5)).x, 1310, accuracy: 10)
        XCTAssertNil(replay.cars[0].position(at: 95))
        let requests = await transport.requests
        XCTAssertTrue(requests.contains { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "date>=" } == true
        })
    }

    func testSubscriptionFailureDoesNotBecomeSyntheticTelemetry() async {
        let transport = FixtureTransport(responses: ["laps": HTTPResponse(data: Data(), status: 401)])
        do {
            _ = try await TrackMapRepository(client: OpenF1Client(transport: transport, requestSpacing: .zero)).load(sessionID: 10)
            XCTFail("Expected the OpenF1 subscription error")
        } catch {
            XCTAssertEqual(error as? APIError, .subscriptionRequired)
        }
    }
}
