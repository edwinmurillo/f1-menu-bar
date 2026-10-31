import XCTest
@testable import F1Core

final class LiveSessionRecordingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testPracticeRanksBestTimesWhileDriversAreOffTrack() throws {
        var recording = LiveSessionRecording(sessionID: "stream-a", meetingName: "Test Grand Prix",
            sessionName: "Practice 1", updatedAt: start)
        var first = snapshot(lap: 2, firstLap: 2, secondLap: 0)
        first.drivers = [driver("1", lap: 2, position: 1, best: "1:20.100"),
                         driver("2", lap: 0, position: 2, best: nil)]
        recording.record(first, at: start.addingTimeInterval(60))
        var second = first
        var outLap = driver("2", lap: 1, position: 1, best: "1:19.900")
        outLap.pitOut = true
        second.drivers = [driver("1", lap: 2, position: 2, best: "1:20.100"), outLap]
        recording.record(second, at: start.addingTimeInterval(120))
        recording.record(second, at: start.addingTimeInterval(130))
        XCTAssertEqual(recording.recordedStepCount, 2, "Unchanged best times must not create a step")
        XCTAssertEqual(recording.practiceSnapshots?[2]?.drivers.count, 2)
        let request = RaceHistoryRequest(weekend: RaceWeekend(id: 1, year: 2027, name: "Test Grand Prix",
            sessions: [RaceSession(id: 11, name: "Practice 1", start: start),
                       RaceSession(id: 12, name: "Race", start: start.addingTimeInterval(172_800))]),
            provider: .openF1, sessionID: 11)
        let history = try XCTUnwrap(LiveRecordingHistory.make(recording, request: request))
        XCTAssertEqual(history.laps.map(\.number), [1, 2])
        XCTAssertEqual(history.laps[1].timings.count, 2)
        XCTAssertEqual(history.laps[0].timings.first(where: { $0.driverID == "1" })?.position, 1)
        XCTAssertNil(history.laps[0].timings.first(where: { $0.driverID == "2" })?.position)
        XCTAssertEqual(history.laps[1].timings.first(where: { $0.driverID == "2" })?.position, 1)
        XCTAssertEqual(history.laps[1].timings.first(where: { $0.driverID == "1" })?.position, 2)
        XCTAssertEqual(history.laps[1].timings.first(where: { $0.driverID == "1" })?.bestDuration, 80.1)
        XCTAssertEqual(history.laps[1].timings.first(where: { $0.driverID == "2" })?.inPit, false)
        XCTAssertEqual(history.laps[1].timings.first(where: { $0.driverID == "2" })?.pitOut, true)
        XCTAssertNil(LiveRecordingHistory.make(recording, request: RaceHistoryRequest(
            weekend: request.weekend, provider: .openF1, sessionID: 12)))
    }

    func testArchiveSurvivesReloadAndRejectsOlderWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = LiveLapArchive(directory: directory)
        var recording = LiveSessionRecording(sessionID: "stream/a", meetingName: "Test Grand Prix",
            sessionName: "Race", updatedAt: start)
        var race = snapshot(lap: 1, firstLap: 1, secondLap: 1, session: "Race")
        race.sessionID = "stream/a"
        recording.record(race, at: start)
        try await archive.save(recording, sequence: 2)
        var old = recording
        old.laps = [:]
        try await archive.save(old, sequence: 1)
        let recovered = try await LiveLapArchive(directory: directory).latest()
        XCTAssertEqual(recovered?.sessionID, "stream/a")
        XCTAssertEqual(recovered?.laps.count, 1)
    }

    private func snapshot(lap: Int, firstLap: Int, secondLap: Int, session: String = "Practice 1") -> LiveTimingSnapshot {
        var value = LiveTimingSnapshot()
        value.sessionID = "stream-a"; value.sessionName = session
        value.meetingName = "Test Grand Prix"; value.sessionStatus = "Started"
        value.currentLap = lap; value.receivedAt = start
        value.drivers = [driver("1", lap: firstLap, position: 1), driver("2", lap: secondLap, position: 2)]
        return value
    }
    private func driver(_ id: String, lap: Int, position: Int, best: String? = "1:19.900") -> LiveDriverTiming {
        LiveDriverTiming(id: id, position: position, name: "Driver \(id)", abbreviation: "D\(id)",
            team: "Team", teamColor: "FFFFFF", gap: position == 1 ? "0" : "+1.2", interval: nil,
            laps: lap, lastLap: "1:20.100", bestLap: best, sectors: [], stops: 0,
            inPit: false, retired: false, knockedOut: false, stints: [])
    }
}
