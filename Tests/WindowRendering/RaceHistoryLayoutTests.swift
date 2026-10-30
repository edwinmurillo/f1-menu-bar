import AppKit
import SwiftUI
import XCTest
@testable import F1Core

@MainActor final class RaceHistoryLayoutTests: XCTestCase {
    func testCalendarTimelineNavigationPreservesRaceIdentity() {
        let coordinator = AppCoordinator()
        let request = fixtureRequest()
        coordinator.showTimeline(request.weekend, provider: request.calendarProvider, at: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(coordinator.section, .timeline)
        XCTAssertEqual(coordinator.timelineRequest, request)
        XCTAssertEqual(coordinator.navigationRevision, 1)
    }
    func testTimelineHasOnePageScrollAndAllDriverRowsInBothAppearances() async throws {
        _ = NSApplication.shared
        let request = fixtureRequest()
        let history = fixtureHistory(request)
        let repository = HistoryLayoutRepository(history: history)
        let state = RaceHistoryStore(repository: repository, now: { Date(timeIntervalSince1970: 1_780_000_000) })
        let season = SeasonStore(repository: HistorySeasonRepository(request: request), clock: { Date(timeIntervalSince1970: 1_780_000_000) })
        await season.refresh(force: true)
        await state.load(request)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "RaceHistoryLayout-\(UUID().uuidString)")!)
        let coordinator = AppCoordinator()
        coordinator.showTimeline(request.weekend, provider: .openF1, at: Date(timeIntervalSince1970: 1_780_000_000))
        let root = RaceTimelineView(season: season, historyStore: state, coordinator: coordinator, preferences: preferences)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 835, height: 720),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close(); season.cancelRefresh(); state.cancel() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 835, height: 720), NSSize(width: 1035, height: 900)] {
                window.setContentSize(size); host.layoutSubtreeIfNeeded()
                let scrolls = scrollViews(host)
                XCTAssertEqual(scrolls.count, 1, "One page scroll; the timing rows must not have an inner scroll")
                XCTAssertGreaterThan(try XCTUnwrap(scrolls.first?.documentView).frame.height, 22 * 50)
                XCTAssertLessThanOrEqual(host.fittingSize.height, host.bounds.height + 1)
            }
            try capture(host, name: appearance == .aqua ? "history-light" : "history-dark")
            if let scroll = scrollViews(host).first, let document = scroll.documentView {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                try capture(host, name: appearance == .aqua ? "history-timing-light" : "history-timing-dark")
                scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }
    func testSeasonWithOnlyFutureRacesHasNoSelectableGrandPrix() async throws {
        let request = RaceHistoryRequest(weekend: RaceWeekend(id: 2, year: 2026, name: "Future GP",
            sessions: [RaceSession(id: 20, name: "Race", start: Date(timeIntervalSince1970: 1_796_558_400))]), provider: .openF1)
        let history = RaceHistory(request: request, provider: .openF1, sourceID: "none", drivers: [], laps: [], events: [], updatedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let state = RaceHistoryStore(repository: HistoryLayoutRepository(history: history), now: { Date(timeIntervalSince1970: 1_780_000_000) })
        await state.load(request)
        XCTAssertTrue(state.history?.drivers.isEmpty == true)
        XCTAssertTrue(state.history?.laps.isEmpty == true)
        let season = SeasonStore(repository: HistorySeasonRepository(request: request), clock: { Date(timeIntervalSince1970: 1_780_000_000) })
        await season.refresh(force: true)
        let coordinator = AppCoordinator(); coordinator.showTimeline(request.weekend, provider: .openF1, at: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertNil(coordinator.timelineRequest, "Calendar navigation must also reject future races")
        XCTAssertEqual(coordinator.section, .calendar)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "RaceHistoryEmpty-\(UUID().uuidString)")!)
        let host = NSHostingView(rootView: RaceTimelineView(season: season, historyStore: state, coordinator: coordinator, preferences: preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 835, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close(); season.cancelRefresh(); state.cancel() }
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrollViews(host).count, 1)
        try capture(host, name: "history-empty")
    }
    private func fixtureRequest() -> RaceHistoryRequest {
        RaceHistoryRequest(weekend: RaceWeekend(id: 1, year: 2026, name: "British Grand Prix",
            circuit: "Silverstone", country: "United Kingdom", sessions: [RaceSession(id: 10, name: "Race", start: Date(timeIntervalSince1970: 1_770_000_000))]), provider: .openF1)
    }
    private func fixtureHistory(_ request: RaceHistoryRequest) -> RaceHistory {
        let drivers = (1...22).map { n in
            RaceHistoryDriver(id: String(n), name: "Fixture Driver \(n)", abbreviation: "D\(n)",
                team: "Fixture Team", teamColor: n.isMultiple(of: 2) ? "27F4D2" : "FF8000")
        }
        let laps = (1...52).map { lap in
            RaceHistoryLap(number: lap, timings: drivers.enumerated().map { i, d in
                RaceHistoryTiming(driverID: d.id, position: i + 1, duration: 90 + Double(i) / 10,
                    bestDuration: 89 + Double(i) / 10, gap: .seconds(Double(i) * 1.2), compound: "MEDIUM", tyreAge: lap, stops: lap > 20 ? 1 : 0)
            })
        }
        return RaceHistory(request: request, provider: .openF1, sourceID: "10", drivers: drivers, laps: laps, events: [], updatedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }
    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
    }
    private func capture(_ host: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: ".build/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appending(path: "\(name).png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}

private struct HistoryLayoutRepository: RaceHistoryRepository {
    let history: RaceHistory
    func cached(_ request: RaceHistoryRequest) async throws -> RaceHistory? { history.request == request ? history : nil }
    func fetch(_ request: RaceHistoryRequest) async throws -> RaceHistory { history }
}
private struct HistorySeasonRepository: SeasonRepository {
    let request: RaceHistoryRequest
    func cached(year: Int) async throws -> SeasonSnapshot? { value(year) }
    func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot { value(year) }
    private func value(_ year: Int) -> SeasonSnapshot {
        var value = SeasonSnapshot(year: year); value.weekends = [request.weekend]; return value
    }
}
