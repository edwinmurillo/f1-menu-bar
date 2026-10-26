import AppKit
import SwiftUI
import XCTest
@testable import F1Core

@MainActor final class StandingsLayoutTests: XCTestCase {
    func testWinLabelsCombineTheSameWeekendAndFlagsUseProviderCountryNames() {
        let weekend = RaceWeekend(id: 1, year: 2026, name: "Las Vegas Grand Prix", country: "USA", sessions: [])
        XCTAssertEqual(SeasonWinPresentation.label(WeekendVictory(weekend: weekend, qualifying: true, grandPrix: true)), "Quali & GP – Las Vegas")
        XCTAssertEqual(SeasonWinPresentation.label(WeekendVictory(weekend: weekend, qualifying: true, grandPrix: false)), "Quali – Las Vegas")
        XCTAssertEqual(SeasonWinPresentation.label(WeekendVictory(weekend: weekend, qualifying: false, grandPrix: true)), "GP – Las Vegas")
        for country in ["USA", "United States", "US"] { XCTAssertEqual(SeasonWinPresentation.flag(country: country), "🇺🇸") }
        for country in ["UK", "Great Britain", "United Kingdom"] { XCTAssertEqual(SeasonWinPresentation.flag(country: country), "🇬🇧") }
        XCTAssertEqual(SeasonWinPresentation.flag(country: "Brazil"), "🇧🇷")
        XCTAssertEqual(SeasonWinPresentation.flag(country: "United Arab Emirates"), "🇦🇪")
        XCTAssertEqual(SeasonWinPresentation.flag(country: "Unknown country"), "🌐")
    }

    func testFullSeasonWinBadgesKeepBothStandingsTablesInsideTheirViewport() throws {
        _ = NSApplication.shared
        let snapshot = fixture()
        for drivers in [true, false] {
            let root = StandingsView(snapshot: snapshot, drivers: drivers, loading: false,
                now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(secondsFromGMT: 0)!)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            for size in [NSSize(width: 800, height: 720), NSSize(width: 1050, height: 900)] {
                window.setContentSize(size)
                host.layoutSubtreeIfNeeded()
                let table = try XCTUnwrap(findTable(host))
                XCTAssertEqual(table.numberOfRows, drivers ? 22 : 11)
                XCTAssertEqual(table.tableColumns.count, 4)
                let scroll = try XCTUnwrap(table.enclosingScrollView)
                let frame = host.convert(scroll.bounds, from: scroll)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertGreaterThanOrEqual(frame.minY, host.bounds.minY - 1)
                XCTAssertLessThanOrEqual(frame.maxY, host.bounds.maxY + 1)
                XCTAssertLessThanOrEqual(host.fittingSize.height, host.bounds.height + 1)
                XCTAssertLessThanOrEqual(host.fittingSize.width, host.bounds.width + 1)
            }
        }
    }

    private func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable($0) }.first
    }

    private func fixture() -> SeasonSnapshot {
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = (1...24).map { round in
            let winner = RaceWinner(driverNumber: 1, driverName: "Fixture Driver 1", team: "Fixture Team 1")
            return RaceWeekend(id: round, year: 2026, name: "Long Fixture Event \(round) Grand Prix", country: "USA",
                sessions: [], winner: winner, qualifyingWinner: winner)
        }
        snapshot.drivers = (1...22).map {
            DriverStanding(driverNumber: $0, position: $0, name: "Fixture Driver \($0)", team: "Fixture Team \($0)", teamColor: nil, points: Double(300 - $0))
        }
        snapshot.constructors = (1...11).map {
            ConstructorStanding(name: "Fixture Team \($0)", position: $0, drivers: "Fixture Driver", color: nil, points: Double(400 - $0))
        }
        snapshot.resultsUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.qualifyingUpdatedAt = snapshot.resultsUpdatedAt
        return snapshot
    }
}
