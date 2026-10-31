import XCTest
@testable import F1Core

final class PR3RegressionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func weekend() -> RaceWeekend {
        RaceWeekend(id: 1, year: 2027, name: "Test Grand Prix", sessions: [
            RaceSession(id: 11, name: "Practice 1", start: start),
            RaceSession(id: 12, name: "Qualifying", start: start.addingTimeInterval(86_400)),
            RaceSession(id: 13, name: "Race", start: start.addingTimeInterval(172_800))])
    }
    private func driver(_ id: String, position: Int, best: String) -> LiveDriverTiming {
        LiveDriverTiming(id: id, position: position, name: "Driver \(id)", abbreviation: "D\(id)",
            team: "Team", teamColor: nil, gap: position == 1 ? "0" : "+0.1", interval: nil,
            laps: 1, lastLap: best, bestLap: best, sectors: [], stops: 0,
            inPit: false, retired: false, knockedOut: false, stints: [])
    }
    func testFutureWeekendUnavailableUntilFirstSessionAndPublishedUnknownRaceStillWorks() {
        XCTAssertFalse(weekend().hasStartedTimelineSession(at: start.addingTimeInterval(-1)))
        XCTAssertTrue(weekend().hasStartedTimelineSession(at: start))
        var unknown = RaceWeekend(id: 2, year: 2027, name: "GP", sessions: [RaceSession(id: 1, name: "Race", start: nil)])
        XCTAssertFalse(unknown.hasStartedTimelineSession(at: start))
        unknown.winner = RaceWinner(driverNumber: 1, driverName: "Winner", team: "Team")
        XCTAssertTrue(unknown.hasStartedTimelineSession(at: start))
        unknown.isCancelled = true
        XCTAssertFalse(unknown.hasStartedTimelineSession(at: start))
    }
    func testExplicitRaceSelectionReusesLegacyDiskFileWithNoSessionID() async throws {
        let request = RaceHistoryRequest(weekend: weekend(), provider: .openF1)
        let explicit = RaceHistoryRequest(weekend: weekend(), provider: .openF1, sessionID: 13)
        XCTAssertEqual(request, explicit)
        XCTAssertEqual(explicit.key, "openf1-2027-1")
        let history = RaceHistory(request: request, provider: .openF1, sourceID: "13", drivers: [],
            laps: [RaceHistoryLap(number: 1, timings: [])], events: [], updatedAt: start)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(history)) as? [String: Any])
        var oldRequest = try XCTUnwrap(json["request"] as? [String: Any])
        oldRequest.removeValue(forKey: "sessionID"); json["request"] = oldRequest
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "race-history-v1/openf1/2027/openf1-2027-1.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: target)
        let restored = try await RaceHistoryCache(directory: directory).load(explicit)
        XCTAssertEqual(restored, history)
        XCTAssertNotEqual(RaceHistoryRequest(weekend: weekend(), provider: .openF1, sessionID: 11).key, request.key)
    }
    func testQualifyingCapturesSlowerResetAndUsesPublishedPositions() throws {
        var recording = LiveSessionRecording(sessionID: "q", meetingName: "Test Grand Prix", sessionName: "Qualifying", updatedAt: start)
        var snapshot = LiveTimingSnapshot()
        snapshot.sessionID = "q"; snapshot.sessionName = "Qualifying"
        snapshot.drivers = [driver("1", position: 1, best: "1:19.000"), driver("2", position: 2, best: "1:20.000")]
        recording.record(snapshot, at: start.addingTimeInterval(86_400))
        snapshot.drivers = [driver("1", position: 2, best: "1:21.000"), driver("2", position: 1, best: "1:22.000")]
        recording.record(snapshot, at: start.addingTimeInterval(86_500))
        XCTAssertEqual(recording.recordedStepCount, 2, "A later qualifying segment must not require an improvement over Q1")
        let request = RaceHistoryRequest(weekend: weekend(), provider: .openF1, sessionID: 12)
        let history = try XCTUnwrap(LiveRecordingHistory.make(recording, request: request))
        XCTAssertEqual(history.laps.last?.timings.first(where: { $0.driverID == "2" })?.position, 1)
        XCTAssertEqual(history.laps.last?.timings.first(where: { $0.driverID == "1" })?.bestDuration, 81)
        recording.meetingName = "Another Grand Prix"
        XCTAssertNil(LiveRecordingHistory.make(recording, request: request), "A nearby timestamp alone does not establish event identity")
    }
    func testRaceWithoutLapCountDoesNotCreatePracticeSteps() {
        var recording = LiveSessionRecording(sessionID: "r", meetingName: "Test Grand Prix", sessionName: "Race", updatedAt: start)
        var snapshot = LiveTimingSnapshot(); snapshot.sessionID = "r"; snapshot.sessionName = "Race"
        snapshot.drivers = [driver("1", position: 1, best: "1:20.000")]
        recording.record(snapshot, at: start)
        XCTAssertEqual(recording.recordedStepCount, 0)
        XCTAssertTrue(recording.practiceSnapshots?.isEmpty == true)
    }
    func testArchiveRejectsDuplicateRosterBeforeItCanReachRanking() async throws {
        var recording = LiveSessionRecording(sessionID: "r", meetingName: "Test Grand Prix", sessionName: "Race", updatedAt: start)
        var snapshot = LiveTimingSnapshot(); snapshot.sessionID = "r"; snapshot.sessionName = "Race"
        let row = driver("1", position: 1, best: "1:20.000"); snapshot.drivers = [row, row]
        recording.laps = [1: snapshot]
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owned = directory.appending(path: "live-laps-v1")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try JSONEncoder().encode(recording).write(to: owned.appending(path: "latest.json"))
        do { _ = try await LiveLapArchive(directory: directory).latest(); XCTFail("Invalid recording was accepted") }
        catch { guard case CacheError.incompatible = error else { return XCTFail("Unexpected error: \(error)") } }
    }
}
