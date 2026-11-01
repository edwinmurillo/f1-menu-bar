import XCTest
@testable import F1Core

final class ChampionshipClinchPolicyTests: XCTestCase {
    private func season() -> SeasonSnapshot {
        var value = SeasonSnapshot(year: 2026)
        value.weekends = [
            RaceWeekend(id: 1, year: 2026, name: "Previous", sessions: [RaceSession(id: 10, name: "Race", start: Date(timeIntervalSince1970: 100))]),
            RaceWeekend(id: 2, year: 2026, name: "Final", sessions: [RaceSession(id: 21, name: "Sprint", start: Date(timeIntervalSince1970: 200)), RaceSession(id: 20, name: "Race", start: Date(timeIntervalSince1970: 300))])
        ]
        return value
    }
    private var context: ChampionshipContext { .init(sessionID: 10, meetingName: "Previous", updatedAt: Date()) }
    func testRemainingCapacityIncludesRaceSprintAndBothTeamCars() {
        let value = season()
        XCTAssertEqual(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: false), 33)
        XCTAssertEqual(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: true), 58)
        let race = RaceHistoryRequest(weekend: value.weekends[1], provider: value.provider)
        XCTAssertEqual(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: false, projectedSession: race), 8)
        let sprint = RaceHistoryRequest(weekend: value.weekends[1], provider: value.provider, sessionID: 21)
        XCTAssertEqual(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: true, projectedSession: sprint), 43)
    }
    func testOnlyAnUncatchableLeadEarnsTrophyAndTiesRemainUnknown() {
        typealias Score = ChampionshipClinchPolicy.Score
        XCTAssertNil(ChampionshipClinchPolicy.championID(scores: [Score(id: "a", points: 133), Score(id: "b", points: 100)], remainingPoints: 33))
        XCTAssertEqual(ChampionshipClinchPolicy.championID(scores: [Score(id: "a", points: 133.5), Score(id: "b", points: 100)], remainingPoints: 33), "a")
        XCTAssertNil(ChampionshipClinchPolicy.championID(scores: [Score(id: "a", points: 100), Score(id: "b", points: 100)], remainingPoints: 0))
        XCTAssertNil(ChampionshipClinchPolicy.championID(scores: [Score(id: "a", points: 999)], remainingPoints: 0))
    }
    func testPublishedPointDeductionsDoNotSuppressAClinch() {
        XCTAssertEqual(ChampionshipClinchPolicy.championID(scores: [.init(id: "leader", points: 100), .init(id: "deducted", points: -2)], remainingPoints: 100), "leader")
    }

    func testUnknownContextScheduleOrDatesNeverClaimAChampion() {
        var value = season()
        XCTAssertNil(ChampionshipClinchPolicy.remainingPoints(in: value, context: nil, constructors: false))
        value.weekends[1].isMissingFromSchedule = true
        XCTAssertNil(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: false))
        value.weekends[1].isMissingFromSchedule = false
        value.weekends[1].sessions[0] = RaceSession(id: 21, name: "Sprint", start: nil)
        XCTAssertNil(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: false))
        value.weekends[1].isCancelled = true
        XCTAssertEqual(ChampionshipClinchPolicy.remainingPoints(in: value, context: context, constructors: false), 0)
    }
}
