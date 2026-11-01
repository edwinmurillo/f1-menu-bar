import XCTest
@testable import F1Core

final class SessionScheduleStatusTests: XCTestCase {
    private let policy = SchedulePolicy()
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testSaturdayMarksFridayPracticesPastAndOnlyFirstFutureSessionNext() throws {
        let weekend = try fixture()
        let now = try date("2026-10-31T12:00:00Z")
        XCTAssertEqual(statuses(weekend, now: now), [.scheduledFinished, .scheduledFinished, .next, nil, nil])
    }

    func testExactStartAndEndUseSuppliedTimesWithoutConfirmingLiveStatus() throws {
        let weekend = try fixture()
        let practice = weekend.sessions[2]
        let start = try XCTUnwrap(practice.start)
        let end = try XCTUnwrap(practice.end)
        XCTAssertEqual(policy.sessionStatus(practice, in: weekend, now: start.addingTimeInterval(-1), timeZone: utc), .next)
        XCTAssertEqual(policy.sessionStatus(practice, in: weekend, now: start, timeZone: utc), .scheduledInProgress)
        XCTAssertEqual(policy.sessionStatus(practice, in: weekend, now: end.addingTimeInterval(-1), timeZone: utc), .scheduledInProgress)
        XCTAssertEqual(policy.sessionStatus(practice, in: weekend, now: end, timeZone: utc), .scheduledFinished)
        XCTAssertEqual(policy.sessionStatus(weekend.sessions[3], in: weekend, now: start, timeZone: utc), .next)
    }

    func testBackupWithNoEndDoesNotInventDurationOrClaimStillRunningBetweenSessions() throws {
        let weekend = try fixture(includeEnds: false)
        let practice = weekend.sessions[2]
        XCTAssertEqual(statuses(weekend, now: try date("2026-10-31T12:00:00Z")), [.scheduledFinished, .scheduledFinished, .next, nil, nil])
        for time in ["2026-10-31T15:00:00Z", "2026-10-31T16:30:00Z"] {
            XCTAssertEqual(policy.sessionStatus(practice, in: weekend, now: try date(time), timeZone: utc), .startPassed)
        }
        XCTAssertEqual(policy.sessionStatus(practice, in: weekend, now: try date("2026-10-31T18:00:00Z"), timeZone: utc), .scheduledFinished)
    }

    func testFallbackRaceWithoutEndKeepsStartedTimetableStateUntilPublishedWinner() throws {
        var weekend = try fixture(includeEnds: false)
        let now = try date("2026-11-01T20:45:00Z")
        let race = try XCTUnwrap(weekend.grandPrix)
        XCTAssertEqual(policy.sessionStatus(race, in: weekend, now: now, timeZone: utc), .startPassed)
        weekend.winner = RaceWinner(driverNumber: 1, driverName: "Winner", team: "Team")
        XCTAssertEqual(policy.sessionStatus(race, in: weekend, now: now, timeZone: utc), .finished)
    }

    func testRaceEndStillAwaitsResultsAndQualifyingResultCannotCompleteRace() throws {
        var weekend = try fixture()
        let winner = RaceWinner(driverNumber: 1, driverName: "Fixture driver", team: "Fixture team")
        weekend.qualifyingWinner = winner
        let now = try date("2026-11-01T20:00:00Z")
        XCTAssertEqual(policy.sessionStatus(weekend.sessions[3], in: weekend, now: now, timeZone: utc), .finished)
        XCTAssertEqual(policy.sessionStatus(weekend.sessions[4], in: weekend, now: now, timeZone: utc), .resultsPending)
        weekend.winner = winner
        XCTAssertEqual(policy.sessionStatus(weekend.sessions[4], in: weekend, now: now, timeZone: utc), .finished)
    }

    func testUnknownInvalidAndCancelledSessionsDoNotGainInventedTimes() throws {
        var weekend = try fixture()
        let now = try date("2026-10-31T16:30:00Z")
        let start = try date("2026-10-31T15:00:00Z")
        let invalid = RaceSession(id: 3, name: "Practice 3", start: start, end: start.addingTimeInterval(-1))
        weekend.sessions[2] = invalid
        XCTAssertEqual(policy.sessionStatus(invalid, in: weekend, now: now, timeZone: utc), .startPassed)
        weekend.sessions[3] = RaceSession(id: 4, name: "Qualifying", start: nil)
        XCTAssertNil(policy.sessionStatus(weekend.sessions[3], in: weekend, now: now, timeZone: utc))
        weekend.sessions[2] = RaceSession(id: 3, name: "Practice 3", start: start, isCancelled: true)
        XCTAssertNil(policy.sessionStatus(weekend.sessions[2], in: weekend, now: now, timeZone: utc))
        XCTAssertEqual(policy.sessionStatus(weekend.sessions[4], in: weekend, now: now, timeZone: utc), .next)
        weekend.isMissingFromSchedule = true
        XCTAssertTrue(statuses(weekend, now: now).allSatisfy { $0 == nil })
        weekend.isMissingFromSchedule = false; weekend.isCancelled = true
        XCTAssertTrue(statuses(weekend, now: now).allSatisfy { $0 == nil })
    }

    func testBadgesOnlyAppearInsideWeekendDatesInSelectedTimezone() throws {
        let weekend = try fixture()
        let madrid = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let first = weekend.sessions[0]
        let madridMidnight = try date("2026-10-29T23:00:00Z")
        XCTAssertNil(policy.sessionStatus(first, in: weekend, now: madridMidnight.addingTimeInterval(-1), timeZone: madrid))
        XCTAssertEqual(policy.sessionStatus(first, in: weekend, now: madridMidnight, timeZone: madrid), .next)
        XCTAssertNil(policy.sessionStatus(first, in: weekend, now: madridMidnight, timeZone: utc))
        let end = try date("2026-11-01T23:00:00Z")
        XCTAssertEqual(policy.sessionStatus(first, in: weekend, now: end.addingTimeInterval(-1), timeZone: madrid), .scheduledFinished)
        XCTAssertNil(policy.sessionStatus(first, in: weekend, now: end, timeZone: madrid))
    }

    func testSprintScheduleUsesTimestampsEvenWhenInputIsUnsorted() throws {
        let regular = try fixture()
        let weekend = RaceWeekend(id: 2, year: 2026, name: "Sprint fixture", sessions: [
            regular.sessions[4],
            RaceSession(id: 11, name: "Sprint Qualifying", start: try date("2026-10-30T18:00:00Z")),
            RaceSession(id: 12, name: "Sprint", start: try date("2026-10-31T15:00:00Z")),
            regular.sessions[0], regular.sessions[3]
        ])
        XCTAssertEqual(statuses(weekend, now: try date("2026-10-31T12:00:00Z")), [nil, .scheduledFinished, .next, .scheduledFinished, nil])
    }

    private func statuses(_ weekend: RaceWeekend, now: Date) -> [SessionScheduleStatus?] {
        weekend.sessions.map { policy.sessionStatus($0, in: weekend, now: now, timeZone: utc) }
    }

    private func fixture(includeEnds: Bool = true) throws -> RaceWeekend {
        let values = [
            ("Practice 1", "2026-10-30T15:00:00Z", "2026-10-30T16:00:00Z"),
            ("Practice 2", "2026-10-30T18:00:00Z", "2026-10-30T19:00:00Z"),
            ("Practice 3", "2026-10-31T15:00:00Z", "2026-10-31T16:00:00Z"),
            ("Qualifying", "2026-10-31T18:00:00Z", "2026-10-31T19:00:00Z"),
            ("Race", "2026-11-01T17:00:00Z", "2026-11-01T19:00:00Z")
        ]
        return RaceWeekend(id: 1, year: 2026, name: "Fixture GP", sessions: try values.enumerated().map { index, value in
            RaceSession(id: index + 1, name: value.0, start: try date(value.1), end: includeEnds ? try date(value.2) : nil)
        })
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }
}
