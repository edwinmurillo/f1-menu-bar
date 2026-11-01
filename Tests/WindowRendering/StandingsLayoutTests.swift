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

    func testRecentWinsUseTheLatestThreeWeekendsAndKeepCombinedWinsTogether() {
        var snapshot = fixture()
        let driver = snapshot.drivers[0]
        snapshot.weekends.reverse()
        let wins = SeasonStatistics.victories(for: driver, in: snapshot)
        XCTAssertEqual(SeasonWinPresentation.recent(wins).map(\.id), [24, 23, 22])
        XCTAssertTrue(SeasonWinPresentation.recent(wins).allSatisfy { $0.qualifying && $0.grandPrix })
        XCTAssertEqual(SeasonWinPresentation.recent(Array(wins.prefix(2))).count, 2)
        XCTAssertTrue(SeasonWinPresentation.recent([]).isEmpty)
        let undated = WeekendVictory(weekend: RaceWeekend(id: 99, year: 2026, name: "Undated", sessions: []), qualifying: true, grandPrix: false)
        XCTAssertEqual(SeasonWinPresentation.recent(wins + [undated]).map(\.id), [24, 23, 22])
        XCTAssertEqual(SeasonWinPresentation.newestFirst(wins + [undated]).last?.id, 99)
    }

    func testDriverStandingsExpandAllRowsInOnePageScrollInBothAppearances() throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: StandingsView(snapshot: fixture(), drivers: true, loading: false,
            now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(secondsFromGMT: 0)!))
        let window = makeWindow(host, size: NSSize(width: 800, height: 720))
        defer { window.contentView = nil; window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 800, height: 720), NSSize(width: 1050, height: 900)] {
                window.setContentSize(size)
                host.layoutSubtreeIfNeeded()
                XCTAssertNil(findTable(host), "Expanded driver rows must not reintroduce a native Table")
                let scrolls = scrollViews(host)
                XCTAssertEqual(scrolls.count, 1, "Driver rows and win previews must share one page scroll")
                let scroll = try XCTUnwrap(scrolls.first)
                let document = try XCTUnwrap(scroll.documentView)
                XCTAssertGreaterThan(document.frame.height, 22 * 60)
                XCTAssertLessThanOrEqual(document.frame.width, scroll.contentView.bounds.width + 1)
                XCTAssertLessThanOrEqual(host.fittingSize.height, size.height + 1)
                XCTAssertLessThanOrEqual(host.fittingSize.width, size.width + 1)
                if size.width == 800 {
                    let suffix = appearance == .aqua ? "light" : "dark"
                    try capture(host, name: "driver-standings-\(suffix)")
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
                    scroll.reflectScrolledClipView(scroll.contentView); host.layoutSubtreeIfNeeded()
                    try capture(host, name: "driver-standings-bottom-\(suffix)")
                    scroll.contentView.scroll(to: .zero)
                }
            }
        }
    }

    func testWinHistoryModalExpandsEveryWeekendWithOneScroll() throws {
        _ = NSApplication.shared
        var snapshot = fixture()
        snapshot.issues[.qualifying] = "Unable to refresh"
        let previousTeam = RaceWinner(driverNumber: 1, driverName: "Fixture Driver 1", team: "Previous Racing Team")
        snapshot.weekends[snapshot.weekends.count - 1].winner = previousTeam
        snapshot.weekends[snapshot.weekends.count - 1].qualifyingWinner = previousTeam
        let host = NSHostingView(rootView: DriverWinsSheet(driver: snapshot.drivers[0], snapshot: snapshot, timeZone: TimeZone(secondsFromGMT: 0)!))
        let window = makeWindow(host, size: NSSize(width: 660, height: 640))
        defer { window.contentView = nil; window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            let scrolls = scrollViews(host)
            XCTAssertEqual(scrolls.count, 1)
            let scroll = try XCTUnwrap(scrolls.first)
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.frame.height, 24 * 180, "Every weekend and both results must be expanded")
            XCTAssertLessThanOrEqual(document.frame.width, scroll.contentView.bounds.width + 1)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 641)
            let suffix = appearance == .aqua ? "light" : "dark"
            try capture(host, name: "driver-wins-modal-\(suffix)")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView); host.layoutSubtreeIfNeeded()
            try capture(host, name: "driver-wins-modal-bottom-\(suffix)")
            scroll.contentView.scroll(to: .zero)
        }
    }

    func testWinPillsStayOnOneLineAndExpandFromThreeToAllOnResize() throws {
        _ = NSApplication.shared
        let snapshot = fixture()
        let wins = Array(SeasonStatistics.victories(for: snapshot.drivers[0], in: snapshot).suffix(6))
        let host = NSHostingView(rootView: SeasonWinsView(victories: wins, drivers: true, qualifyingAvailable: true,
            racesAvailable: true, driverName: "Fixture Driver 1", showAll: {})
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = makeWindow(host, size: NSSize(width: 390, height: 100))
        defer { window.contentView = nil; window.close() }
        for width in [390, 1000, 1800, 390] {
            window.setContentSize(NSSize(width: width, height: 100))
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(scrollViews(host).isEmpty)
            XCTAssertEqual(host.bounds.width, CGFloat(width), accuracy: 1)
            try capture(host, name: "wins-preview-\(width)")
        }
    }

    func testFullSeasonConstructorWinsKeepTableInsideItsViewport() throws {
        _ = NSApplication.shared
        let snapshot = fixture()
        for drivers in [false] {
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

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
    }

    private func makeWindow(_ host: NSView, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        return window
    }

    private func capture(_ host: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: ".build/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appending(path: name + ".png"))
    }

    private func fixture() -> SeasonSnapshot {
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = (1...24).map { round in
            let winner = RaceWinner(driverNumber: 1, driverName: "Fixture Driver 1", team: "Fixture Team 1")
            let race = Date(timeIntervalSince1970: 1_770_000_000 + Double(round) * 604800)
            return RaceWeekend(id: round, year: 2026, name: "Long Fixture Event \(round) Grand Prix", circuit: "Fixture circuit", country: "USA", location: "Fixture city",
                sessions: [RaceSession(id: round * 10, name: "Qualifying", start: race.addingTimeInterval(-86400)),
                    RaceSession(id: round * 10 + 1, name: "Race", start: race)], winner: winner, qualifyingWinner: winner)
        }
        snapshot.drivers = (1...22).map {
            DriverStanding(driverNumber: $0, position: $0, name: "Fixture Driver \($0)", team: "Fixture Team \($0)", teamColor: nil, points: Double(300 - $0))
        }
        snapshot.constructors = (1...11).map {
            ConstructorStanding(name: "Fixture Team \($0)", position: $0, drivers: "Fixture Driver", color: nil, points: Double(400 - $0))
        }
        snapshot.resultsUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.qualifyingUpdatedAt = snapshot.resultsUpdatedAt
        snapshot.driverContext = ChampionshipContext(sessionID: 241, meetingName: snapshot.weekends.last!.name, updatedAt: snapshot.resultsUpdatedAt!)
        snapshot.constructorContext = snapshot.driverContext
        return snapshot
    }
}
