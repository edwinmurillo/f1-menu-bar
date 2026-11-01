import AppKit
import SwiftUI
import XCTest
@testable import F1Core

@MainActor final class StandingsSimulationTests: XCTestCase {
    private func inputs() -> (SeasonSnapshot, LiveTimingSnapshot) {
        let date = ISO8601DateFormatter().date(from: "2026-11-01T21:00:00Z")!
        var season = SeasonSnapshot(year: 2026)
        season.weekends = [RaceWeekend(id: 1, year: 2026, name: "Test GP", sessions: [RaceSession(id: 10, name: "Race", start: date)])]
        season.drivers = [
            DriverStanding(driverNumber: 1, position: 1, name: "One", team: "Team", teamColor: nil, points: 100.5),
            DriverStanding(driverNumber: 2, position: 2, name: "Two", team: "Team", teamColor: nil, points: 95)
        ]
        season.constructors = [ConstructorStanding(name: "Team", position: 1, drivers: "One, Two", color: nil, points: 195.5)]
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
    func testFullFieldTotalsRerankAndAggregateTeammatesWithoutChangingBaseline() {
        let (season, timing) = inputs()
        let result = StandingsSimulation.make(season: season, timing: timing)
        XCTAssertEqual(result.drivers.map(\.name), ["Two", "One"])
        XCTAssertEqual(result.drivers.map(\.total), [120, 118.5])
        XCTAssertEqual(result.teams.first?.added, 43)
        XCTAssertEqual(result.teams.first?.total, 238.5)
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
