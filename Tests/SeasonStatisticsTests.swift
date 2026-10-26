import XCTest
@testable import F1Core

final class SeasonStatisticsTests: XCTestCase {
    func testQualifyingAndGrandPrixWinsCombineByEventAndStayChronological() {
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [weekend(3, race: winner), weekend(1, race: winner, qualifying: winner), weekend(2, qualifying: winner)]
        let wins = SeasonStatistics.victories(for: driver, in: snapshot)
        XCTAssertEqual(wins.map(\.id), [1, 2, 3])
        XCTAssertEqual(wins.filter(\.qualifying).count, 2)
        XCTAssertEqual(wins.filter(\.grandPrix).count, 2)
        XCTAssertTrue(wins[0].qualifying && wins[0].grandPrix)
    }

    func testProviderIdentitySurvivesCarNumberChangeAndRejectsAnotherDriverUsingThatNumber() {
        var snapshot = SeasonSnapshot(year: 2026)
        var another = winner
        another.driverID = "another-driver"
        snapshot.weekends = [weekend(1, race: winner), weekend(2, race: another)]
        // The result uses car 1 while the standing retains permanent number 9.
        XCTAssertEqual(SeasonStatistics.victories(for: driver, in: snapshot).map(\.id), [1])
        let otherStanding = DriverStanding(driverID: "someone-else", driverNumber: 1, position: 2,
            name: "Fixture Winner", team: "Coral", teamColor: nil, points: 20)
        XCTAssertTrue(SeasonStatistics.victories(for: otherStanding, in: snapshot).isEmpty)
    }

    func testConstructorWinsFollowTheTeamAtThatRaceAndIncludeBothDrivers() {
        var teammate = winner
        teammate.driverID = "teammate"
        var transferred = winner
        transferred.constructorID = "indigo"
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [weekend(1, race: winner), weekend(2, race: teammate),
            weekend(3, race: transferred), weekend(4, qualifying: winner)]
        let constructor = ConstructorStanding(constructorID: "coral", name: "Renamed Coral", position: 1,
            drivers: "", color: nil, points: 40)
        let wins = SeasonStatistics.victories(for: constructor, in: snapshot)
        XCTAssertEqual(wins.map(\.id), [1, 2])
        XCTAssertTrue(wins.allSatisfy { $0.grandPrix && !$0.qualifying })
    }

    func testUnavailableCancelledAndOtherSeasonEventsDoNotCount() {
        var cancelled = weekend(1, race: winner); cancelled.isCancelled = true
        var missing = weekend(2, race: winner); missing.isMissingFromSchedule = true
        let oldSeason = RaceWeekend(id: 3, year: 2025, name: "Old GP", sessions: [], winner: winner)
        var cancelledQualifying = weekend(4, race: winner, qualifying: winner)
        cancelledQualifying.sessions.append(RaceSession(id: 42, name: "Qualifying", start: nil, isCancelled: true))
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [cancelled, missing, oldSeason, cancelledQualifying]
        let wins = SeasonStatistics.victories(for: driver, in: snapshot)
        XCTAssertEqual(wins.map(\.id), [4])
        XCTAssertFalse(wins[0].qualifying)
        XCTAssertTrue(wins[0].grandPrix)
    }

    func testOpenF1AndLegacyCachedWinnersCanMatchWithoutProviderIDs() {
        let legacy = RaceWinner(driverNumber: 9, driverName: "Fixture Winner", team: "Coral")
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [weekend(1, race: legacy)]
        XCTAssertEqual(SeasonStatistics.victories(for: driver, in: snapshot).count, 1)
        let constructor = ConstructorStanding(name: "coral", position: 1, drivers: "", color: nil, points: 25)
        XCTAssertEqual(SeasonStatistics.victories(for: constructor, in: snapshot).count, 1)
    }

    func testExistingCacheDecodesWithoutNewStatisticsFields() throws {
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [weekend(1, race: winner)]
        snapshot.drivers = [driver]
        snapshot.constructors = [ConstructorStanding(name: "Coral", position: 1, drivers: "", color: nil, points: 25)]
        snapshot.resultsUpdatedAt = Fixtures.now
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var weekends = try XCTUnwrap(object["weekends"] as? [[String: Any]])
        var result = try XCTUnwrap(weekends[0]["winner"] as? [String: Any])
        result.removeValue(forKey: "driverID"); result.removeValue(forKey: "constructorID")
        weekends[0]["winner"] = result
        weekends[0].removeValue(forKey: "qualifyingWinner")
        object["weekends"] = weekends
        object.removeValue(forKey: "qualifyingUpdatedAt")
        let decoded = try JSONDecoder().decode(SeasonSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.weekends[0].winner?.driverName, "Fixture Winner")
        XCTAssertNil(decoded.weekends[0].winner?.driverID)
        XCTAssertNil(decoded.weekends[0].qualifyingWinner)
        XCTAssertNil(decoded.qualifyingUpdatedAt)
        XCTAssertNil(decoded.constructors[0].constructorID)
        XCTAssertEqual(decoded.drivers, snapshot.drivers)
    }

    private var driver: DriverStanding {
        DriverStanding(driverID: "winner", driverNumber: 9, position: 1, name: "Fixture Winner", team: "Indigo", teamColor: nil, points: 25)
    }
    private var winner: RaceWinner {
        RaceWinner(driverNumber: 1, driverName: "Fixture Winner", team: "Coral", driverID: "winner", constructorID: "coral")
    }
    private func weekend(_ id: Int, race: RaceWinner? = nil, qualifying: RaceWinner? = nil) -> RaceWeekend {
        RaceWeekend(id: id, year: 2026, name: "Fixture \(id) Grand Prix",
            sessions: [RaceSession(id: id * 10, name: "Race", start: Fixtures.now.addingTimeInterval(Double(id)))],
            winner: race, qualifyingWinner: qualifying)
    }
}
