import AppKit
import SwiftUI
import XCTest
@testable import F1Core

@MainActor final class StandingsSimulationTests: XCTestCase {
    private func inputs() -> (SeasonSnapshot, LiveTimingSnapshot) {
        let date = ISO8601DateFormatter().date(from: "2026-11-01T21:00:00Z")!
        var season = SeasonSnapshot(year: 2026)
        season.weekends = [RaceWeekend(id: 1, year: 2026, name: "Test GP", sessions: [RaceSession(id: 10, name: "Race", start: date)])]
        season.weekends.insert(RaceWeekend(id: 0, year: 2026, name: "Previous GP", sessions: [RaceSession(id: 0, name: "Race", start: date.addingTimeInterval(-7 * 86400))]), at: 0)
        season.driverContext = ChampionshipContext(sessionID: 0, meetingName: "Previous GP", updatedAt: date)
        season.constructorContext = season.driverContext
        season.drivers = [
            DriverStanding(driverNumber: 1, position: 1, name: "One", team: "Team", teamColor: nil, points: 100.5),
            DriverStanding(driverNumber: 2, position: 2, name: "Two", team: "Team", teamColor: nil, points: 95)
        ]
        season.constructors = [ConstructorStanding(name: "Team", position: 1, drivers: "One, Two", color: nil, points: 195.5), ConstructorStanding(name: "Other", position: 2, drivers: "", color: nil, points: 190)]
        var timing = LiveTimingSnapshot()
        timing.meetingName = "Test GP"; timing.sessionName = "Race"; timing.receivedAt = date
        timing.drivers = [driver("1", position: 2), driver("2", position: 1)]
        return (season, timing)
    }
    private func driver(_ id: String, position: Int) -> LiveDriverTiming {
        LiveDriverTiming(id: id, position: position, name: id, abbreviation: id, team: "Team", teamColor: nil,
            gap: nil, interval: nil, laps: nil, lastLap: nil, bestLap: nil, sectors: [], stops: nil,
            inPit: false, retired: false, knockedOut: false, stints: [])
    }
    func testAntonelliProjectionClinchesWithFourRacesRemaining() {
        var (season, timing) = inputs()
        let date = timing.receivedAt!
        for index in 1...4 {
            season.weekends.append(RaceWeekend(id: 100 + index, year: 2026, name: "Remaining GP \(index)", sessions: [RaceSession(id: 1000 + index, name: "Race", start: date.addingTimeInterval(Double(index) * 7 * 86400))]))
        }
        let entries: [(Int, String, String, Double, Int)] = [
            (12, "Kimi Antonelli", "Mercedes", 365, 3),
            (3, "Max Verstappen", "Red Bull Racing", 236, 1),
            (44, "Lewis Hamilton", "Ferrari", 241, 2),
            (63, "George Russell", "Mercedes", 242, 6)
        ]
        season.drivers = entries.map { DriverStanding(driverNumber: $0.0, position: nil, name: $0.1, team: $0.2, teamColor: nil, points: $0.3) }
        season.constructors = [] // An unavailable team projection must not hide the driver's cup.
        timing.drivers = entries.map { LiveDriverTiming(id: String($0.0), position: $0.4, name: $0.1, abbreviation: "", team: $0.2, teamColor: nil,
            gap: nil, interval: nil, laps: nil, lastLap: nil, bestLap: nil, sectors: [], stops: nil, inPit: false, retired: false, knockedOut: false, stints: []) }
        let result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertEqual(result.drivers.first?.name, "Kimi Antonelli")
        XCTAssertEqual(result.drivers.first?.total, 380)
        XCTAssertEqual(result.drivers[1].total, 261)
        XCTAssertEqual(result.drivers.first?.isChampion, true)
        let current = RaceHistoryRequest(weekend: season.weekends[1], provider: season.provider)
        XCTAssertEqual(ChampionshipClinchPolicy.remainingPoints(in: season, context: season.driverContext, constructors: false, projectedSession: current), 100)
    }

    func testMissingLivePositionDoesNotInventAChampionshipClinch() {
        let (season, initialTiming) = inputs()
        var timing = initialTiming
        timing.drivers[1] = LiveDriverTiming(id: "2", position: nil, name: "Two", abbreviation: "TWO", team: "Team", teamColor: nil,
            gap: nil, interval: nil, laps: nil, lastLap: nil, bestLap: nil, sectors: [], stops: nil, inPit: false, retired: false, knockedOut: false, stints: [])
        var result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertTrue(result.drivers.allSatisfy { !$0.isChampion })
        timing.drivers = []
        result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertTrue(result.drivers.allSatisfy { !$0.isChampion })
    }

    func testDriverChampionIsNotBlockedByUnmatchedConstructor() {
        var (season, timing) = inputs()
        season.constructors = []
        let result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertEqual(result.drivers.filter(\.isChampion).map(\.name), ["Two"])
        XCTAssertTrue(result.notes.contains { $0.contains("team points are unassigned") })
    }
    func testCurrentLiveTeamWinsOverMultipleHistoricalDriverTeams() {
        var (season, timing) = inputs()
        season.drivers[1] = DriverStanding(driverNumber: 2, position: 2, name: "Two", team: "RB F1 Team / Red Bull", teamColor: nil, points: 95)
        season.constructors = [ConstructorStanding(name: "RB F1 Team", position: 1, drivers: "", color: nil, points: 100), ConstructorStanding(name: "Red Bull", position: 2, drivers: "", color: nil, points: 90)]
        timing.drivers = [LiveDriverTiming(id: "2", position: 1, name: "Two", abbreviation: "TWO", team: "Racing Bulls", teamColor: nil,
            gap: nil, interval: nil, laps: nil, lastLap: nil, bestLap: nil, sectors: [], stops: nil, inPit: false, retired: false, knockedOut: false, stints: [])]
        let result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertEqual(result.teams.first { $0.name == "RB F1 Team" }?.added, 25)
        XCTAssertEqual(result.teams.first { $0.name == "Red Bull" }?.added, 0)
        XCTAssertFalse(result.notes.contains { $0.contains("unassigned") })
        XCTAssertEqual(result.drivers.filter(\.isChampion).map(\.name), ["Two"])
    }

    func testFullFieldTotalsRerankAndAggregateTeammatesWithoutChangingBaseline() {
        let (season, timing) = inputs()
        let result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertEqual(result.drivers.map(\.name), ["Two", "One"])
        XCTAssertEqual(result.drivers.map(\.total), [120, 118.5])
        XCTAssertEqual(result.teams.first?.added, 43)
        XCTAssertEqual(result.teams.first?.total, 238.5)
        XCTAssertEqual(result.drivers.filter(\.isChampion).map(\.name), ["Two"])
        XCTAssertEqual(result.teams.filter(\.isChampion).map(\.name), ["Team"])
        XCTAssertEqual(season.drivers.first?.points, 100.5)
    }
    func testAlreadyIncludedAndWrongYearDoNotDoubleCount() {
        var (season, timing) = inputs()
        let context = ChampionshipContext(sessionID: 10, meetingName: "Test GP", updatedAt: timing.receivedAt!)
        season.driverContext = context; season.constructorContext = context
        var result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertTrue(result.drivers.allSatisfy { $0.added == 0 })
        XCTAssertEqual(result.teams.first?.added, 0)
        season.driverContext = nil; season.constructorContext = nil
        timing.receivedAt = ISO8601DateFormatter().date(from: "2025-11-01T21:00:00Z")!
        result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertTrue(result.drivers.allSatisfy { $0.added == 0 })
    }
    func testUnknownRosterIsReportedRatherThanDroppedSilently() {
        var (season, timing) = inputs()
        timing.drivers = [driver("99", position: 1)]
        let result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertTrue(result.notes.contains { $0.contains("unassigned") })
        XCTAssertTrue(result.drivers.allSatisfy { $0.added == 0 })
        season.constructors = []
        timing.drivers = [driver("1", position: 1)]
        XCTAssertTrue(StandingsSimulation.make(season: season, timing: timing).notes.contains { $0.contains("team points are unassigned") })
    }
    func testModalTabsFitWithinBoundedWindow() throws {
        _ = NSApplication.shared
        let (season, timing) = inputs()
        let view = StandingsSimulationSheet(simulation: .make(season: season, timing: timing))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.height, 651)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appending(path: "standings-simulation-dark.png"))
    }
}
