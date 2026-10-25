import XCTest
@testable import F1Core

final class SchedulePolicyTests: XCTestCase {
    private let policy = SchedulePolicy()
    private let raceStart = Date(timeIntervalSince1970: 1_800_000_000)
    private func weekend(_ id: Int = 1, offset: TimeInterval = 0, cancelled: Bool = false, winner: Bool = false) -> RaceWeekend {
        RaceWeekend(id: id, year: 2026, name: "Fixture GP", sessions: [
            RaceSession(id: id * 10, name: "Practice 1", start: raceStart.addingTimeInterval(offset - 172800)),
            RaceSession(id: id * 10 + 1, name: "Qualifying", start: raceStart.addingTimeInterval(offset - 86400)),
            RaceSession(id: id * 10 + 2, name: "Race", start: raceStart.addingTimeInterval(offset))
        ], isCancelled: cancelled, winner: winner ? RaceWinner(driverNumber: 9, driverName: "Fixture Driver", team: "Fixture Team") : nil)
    }
    func testBeforeWeekendSelectsEarliestUpcomingAndPractice() {
        let first = weekend(), second = weekend(2, offset: 604800)
        let now = raceStart.addingTimeInterval(-200000)
        XCTAssertEqual(policy.featured(in: [second, first], now: now)?.id, first.id)
        XCTAssertEqual(policy.nextSession(in: first, now: now)?.name, "Practice 1")
        XCTAssertEqual(policy.status(of: first, in: [first, second], now: now), .next)
    }
    func testKeepsCurrentWeekendBetweenSessions() {
        let current = weekend(), now = raceStart.addingTimeInterval(-100000)
        XCTAssertEqual(policy.featured(in: [current], now: now)?.id, current.id)
        XCTAssertEqual(policy.nextSession(in: current, now: now)?.name, "Qualifying")
        XCTAssertEqual(policy.status(of: current, in: [current], now: now), .current)
    }
    func testRaceStartAndEndDoNotEstablishCompletion() {
        let current = weekend()
        XCTAssertEqual(policy.status(of: current, in: [current], now: raceStart), .resultsPending)
        XCTAssertEqual(policy.featured(in: [current], now: raceStart.addingTimeInterval(3 * 3600))?.id, current.id)
        XCTAssertNil(policy.nextSession(in: current, now: raceStart))
    }
    func testAfterSixHoursAdvancesButPreservesPendingStatus() {
        let current = weekend(), next = weekend(2, offset: 604800), now = raceStart.addingTimeInterval(6 * 3600)
        XCTAssertEqual(policy.featured(in: [current, next], now: now)?.id, next.id)
        XCTAssertEqual(policy.status(of: current, in: [current, next], now: now), .resultsPending)
    }
    func testPublishedWinnerAdvancesImmediately() {
        let done = weekend(winner: true), next = weekend(2, offset: 604800)
        XCTAssertEqual(policy.featured(in: [done, next], now: raceStart)?.id, next.id)
        XCTAssertEqual(policy.status(of: done, in: [done, next], now: raceStart), .raced)
    }
    func testCancelledAndRemovedMeetingsCannotBecomeFeatured() {
        let cancelled = weekend(cancelled: true)
        var removed = weekend(2, offset: 604800); removed.isMissingFromSchedule = true
        let future = weekend(3, offset: 1209600)
        XCTAssertEqual(policy.featured(in: [cancelled, removed, future], now: raceStart.addingTimeInterval(-200000))?.id, future.id)
        XCTAssertEqual(policy.status(of: cancelled, in: [cancelled], now: raceStart), .cancelled)
        XCTAssertEqual(policy.status(of: removed, in: [removed], now: raceStart), .unavailable)
    }
    func testMissingTimeDoesNotProduceCountdown() {
        let race = RaceWeekend(id: 1, year: 2026, name: "Time TBC", sessions: [RaceSession(id: 1, name: "Race", start: nil)])
        XCTAssertNotNil(policy.featured(in: [race], now: raceStart))
        XCTAssertNil(policy.nextSession(in: race, now: raceStart))
    }
    func testDSTAndSaturdayRaceUseAbsoluteTime() throws {
        let parser = ISO8601DateFormatter()
        let start = try XCTUnwrap(parser.date(from: "2026-11-22T04:00:00Z"))
        var local = Calendar(identifier: .gregorian); local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(local.component(.weekday, from: start), 7)
        var madrid = Calendar(identifier: .gregorian); madrid.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let before = try XCTUnwrap(parser.date(from: "2026-10-25T00:30:00Z"))
        let after = try XCTUnwrap(parser.date(from: "2026-10-25T01:30:00Z"))
        XCTAssertEqual(madrid.component(.hour, from: before), madrid.component(.hour, from: after))
        let race = RaceWeekend(id: 1, year: 2026, name: "DST GP", sessions: [RaceSession(id: 1, name: "Race", start: after)])
        XCTAssertEqual(policy.nextSession(in: race, now: before)?.id, 1)
        XCTAssertNil(policy.nextSession(in: race, now: after))
    }
    func testSeasonRolloverWaitsForCompletedOrExpiredFocus() {
        var snapshot = SeasonSnapshot(year: 2026); snapshot.weekends = [weekend()]
        XCTAssertFalse(policy.shouldCheckNextSeason(snapshot, now: raceStart))
        XCTAssertTrue(policy.shouldCheckNextSeason(snapshot, now: raceStart.addingTimeInterval(21600)))
    }

    func testOngoingBeginsAtMidnightOnFirstSessionDateAndIncludesGaps() throws {
        let madrid = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let current = try datedWeekend(first: "2026-10-23T16:30:00Z", race: "2026-10-25T20:00:00Z")
        let firstMidnight = try instant("2026-10-22T22:00:00Z")
        XCTAssertFalse(policy.isOngoing(current, now: firstMidnight.addingTimeInterval(-1), timeZone: madrid))
        XCTAssertTrue(policy.isOngoing(current, now: firstMidnight, timeZone: madrid))
        XCTAssertTrue(policy.isOngoing(current, now: try instant("2026-10-24T10:00:00Z"), timeZone: madrid))
    }

    func testOngoingIncludesRaceDayAndEndsAtNextMidnightAcrossDST() throws {
        let madrid = try XCTUnwrap(TimeZone(identifier: "Europe/Madrid"))
        let current = try datedWeekend(first: "2026-10-23T16:30:00Z", race: "2026-10-25T20:00:00Z")
        // Madrid changes from UTC+2 to UTC+1 during this weekend.
        let end = try instant("2026-10-25T23:00:00Z")
        XCTAssertTrue(policy.isOngoing(current, now: try instant("2026-10-25T00:30:00Z"), timeZone: madrid))
        XCTAssertTrue(policy.isOngoing(current, now: try instant("2026-10-25T01:30:00Z"), timeZone: madrid))
        XCTAssertTrue(policy.isOngoing(current, now: end.addingTimeInterval(-1), timeZone: madrid))
        XCTAssertFalse(policy.isOngoing(current, now: end, timeZone: madrid))
    }

    func testOngoingUsesSelectedTimezoneForSaturdayRace() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let current = try datedWeekend(first: "2026-11-20T00:30:00Z", race: "2026-11-22T04:00:00Z")
        let sundayInLosAngeles = try instant("2026-11-22T08:00:00Z")
        XCTAssertFalse(policy.isOngoing(current, now: sundayInLosAngeles, timeZone: losAngeles))
        XCTAssertTrue(policy.isOngoing(current, now: sundayInLosAngeles, timeZone: utc))
    }

    func testCompletedCancelledAndRemovedWeekendsAreNotOngoing() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var removed = weekend(); removed.isMissingFromSchedule = true
        var cancelledRace = weekend()
        cancelledRace.sessions[cancelledRace.sessions.count - 1] = RaceSession(id: 12, name: "Race", start: raceStart, isCancelled: true)
        for value in [weekend(winner: true), weekend(cancelled: true), removed, cancelledRace] {
            XCTAssertFalse(policy.isOngoing(value, now: raceStart, timeZone: zone))
        }
    }

    func testMissingRaceDateCannotEstablishAnOngoingWeekend() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let unknown = RaceWeekend(id: 1, year: 2026, name: "Time TBC", sessions: [
            RaceSession(id: 1, name: "Practice 1", start: raceStart.addingTimeInterval(-86400)),
            RaceSession(id: 2, name: "Race", start: nil)
        ])
        XCTAssertFalse(policy.isOngoing(unknown, now: raceStart, timeZone: zone))
    }

    private func datedWeekend(first: String, race: String) throws -> RaceWeekend {
        RaceWeekend(id: 1, year: 2026, name: "Fixture GP", sessions: [
            RaceSession(id: 1, name: "Practice 1", start: try instant(first)),
            RaceSession(id: 2, name: "Race", start: try instant(race))
        ])
    }

    private func instant(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
