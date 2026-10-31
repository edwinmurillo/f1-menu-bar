import XCTest
@testable import F1Core

final class RaceHistoryEligibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testEligibilityUsesTheGrandPrixStartRatherThanEarlierPractice() {
        XCTAssertFalse(weekend(start: now.addingTimeInterval(1)).isEligibleForTimeline(at: now))
        XCTAssertTrue(weekend(start: now).isEligibleForTimeline(at: now))
        XCTAssertTrue(weekend(start: now.addingTimeInterval(-1)).isEligibleForTimeline(at: now))
        XCTAssertFalse(weekend(start: nil).isEligibleForTimeline(at: now))
    }

    func testUnavailableRacesAreExcludedAndPublishedResultsResolveUnknownTimes() {
        var race = weekend(start: now.addingTimeInterval(-3600))
        race.isCancelled = true
        XCTAssertFalse(race.isEligibleForTimeline(at: now))
        race.isCancelled = false; race.isMissingFromSchedule = true
        XCTAssertFalse(race.isEligibleForTimeline(at: now))
        race = weekend(start: nil)
        race.winner = RaceWinner(driverNumber: 1, driverName: "Published winner", team: "Team")
        XCTAssertTrue(race.isEligibleForTimeline(at: now))
        race = weekend(start: now.addingTimeInterval(-3600))
        race.sessions[1] = RaceSession(id: 2, name: "Race", start: now.addingTimeInterval(-3600), isCancelled: true)
        XCTAssertFalse(race.isEligibleForTimeline(at: now))
    }

    func testSessionSelectionKeepsHistoryAndCacheKeysSeparate() {
        let race = weekend(start: now.addingTimeInterval(86_400))
        let practice = RaceHistoryRequest(weekend: race, provider: .openF1, sessionID: 1)
        let grandPrix = RaceHistoryRequest(weekend: race, provider: .openF1, sessionID: 2)
        XCTAssertEqual(practice.session?.name, "Practice 1")
        XCTAssertEqual(grandPrix.session?.name, "Race")
        XCTAssertNotEqual(practice.key, grandPrix.key)
        XCTAssertNotEqual(practice, grandPrix)
    }

    func testCurrentWeekendCanHaveStartedPracticeBeforeRace() {
        let race = weekend(start: now.addingTimeInterval(86_400))
        XCTAssertFalse(race.isEligibleForTimeline(at: now))
        XCTAssertTrue(race.activeSessions.contains { ($0.start ?? .distantFuture) <= now })
    }

    private func weekend(start: Date?) -> RaceWeekend {
        RaceWeekend(id: 1, year: 2026, name: "Test Grand Prix", sessions: [
            RaceSession(id: 1, name: "Practice 1", start: now.addingTimeInterval(-86_400)),
            RaceSession(id: 2, name: "Race", start: start)])
    }
}
