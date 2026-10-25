import XCTest
@testable import F1Core

final class ClientAndCacheTests: XCTestCase {
    func testOversizedPayloadIsRejectedBeforeDecoding() async throws {
        let transport = FixtureTransport(responses: ["meetings": HTTPResponse(data: Data(repeating: 32, count: 6_000_001), status: 200)])
        let client = OpenF1Client(transport: transport, requestSpacing: .zero)
        do {
            let _: [MeetingDTO] = try await client.get("meetings", query: [])
            XCTFail("Expected a bounded response")
        } catch APIError.responseTooLarge { }
    }
    func testRateLimitPreventsAnImmediateSecondRequest() async throws {
        let transport = FixtureTransport(responses: ["meetings": HTTPResponse(data: Data(), status: 429, retryAfter: "120")])
        let client = OpenF1Client(transport: transport, requestSpacing: .zero)
        for _ in 0..<2 {
            do {
                let _: [MeetingDTO] = try await client.get("meetings", query: [])
                XCTFail("Expected rate limiting")
            } catch APIError.rateLimited { }
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
    func testHTTPDateRetryAfterIsRespected() {
        let now = Date(timeIntervalSince1970: 0)
        let date = OpenF1Client.retryDate("Thu, 01 Jan 1970 00:02:00 GMT", now: now)
        XCTAssertEqual(date.timeIntervalSince(now), 120)
    }
    func testMalformedResponseIsDifferentFromEmptyValidResponse() async throws {
        let empty = OpenF1Client(transport: FixtureTransport(responses: ["meetings": Fixtures.json("[]")]), requestSpacing: .zero)
        let rows: [MeetingDTO] = try await empty.get("meetings", query: [])
        XCTAssertTrue(rows.isEmpty)
        let broken = OpenF1Client(transport: FixtureTransport(responses: ["meetings": Fixtures.json("{}")]), requestSpacing: .zero)
        do {
            let _: [MeetingDTO] = try await broken.get("meetings", query: [])
            XCTFail("Expected malformed response error")
        } catch APIError.invalidData { }
    }
    func testDiskCacheRoundTripAndCorruptionRemainDistinctFromMissingData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCache(directory: root)
        let absent = try await cache.load(year: 2026)
        XCTAssertNil(absent)
        var value = SeasonSnapshot(year: 2026); value.scheduleUpdatedAt = Fixtures.now
        try await cache.save(value)
        let restored = try await cache.load(year: 2026)
        XCTAssertEqual(restored, value)
        let file = root.appendingPathComponent("openf1-v1/2026.json")
        try Data("broken".utf8).write(to: file)
        do { _ = try await cache.load(year: 2026); XCTFail("Corruption cannot be an empty cache") }
        catch CacheError.incompatible { }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "broken")
    }
}
