import AppKit
import SwiftUI
import XCTest
@testable import F1Core

@MainActor final class NextWeekendLayoutTests: XCTestCase {
    func testOngoingRequiresMatchingFreshSessionEvenAfterScheduledEnd() throws {
        let parser = ISO8601DateFormatter()
        let weekend = try XCTUnwrap(fixture(parser).weekends.first)
        let race = try XCTUnwrap(weekend.grandPrix)
        let now = try XCTUnwrap(parser.date(from: "2026-11-01T20:00:00Z"))
        var live = LiveTimingSnapshot()
        live.meetingName = weekend.name; live.sessionName = race.name
        live.sessionStatus = "Started"; live.lastTimingUpdate = now
        var view = SessionScheduleView(weekend: weekend, now: now, zone: TimeZone(secondsFromGMT: 0)!, liveSnapshot: live)
        XCTAssertTrue(view.isLive(race))
        live.lastTimingUpdate = now.addingTimeInterval(-31); view.liveSnapshot = live
        XCTAssertFalse(view.isLive(race))
        live.lastTimingUpdate = now; live.sessionStatus = "Finished"; view.liveSnapshot = live
        XCTAssertFalse(view.isLive(race))
        live.sessionStatus = "Started"; live.meetingName = "Another Grand Prix"; view.liveSnapshot = live
        XCTAssertFalse(view.isLive(race))
    }

    func testSessionBadgesFitTheMenuPanelInBothAppearances() async throws {
        _ = NSApplication.shared
        let parser = ISO8601DateFormatter()
        let snapshot = try fixture(parser)
        let defaults = UserDefaults(suiteName: "SessionBadges-\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        preferences.useUTC = true
        for (name, instant) in [
            ("between-sessions", "2026-10-31T12:00:00Z"),
            ("in-progress", "2026-10-31T15:30:00Z"),
            ("results-pending", "2026-11-01T20:00:00Z"),
            ("fallback-ongoing", "2026-11-01T20:45:00Z")
        ] {
            let now = try XCTUnwrap(parser.date(from: instant))
            var panelSnapshot = snapshot
            if name == "fallback-ongoing" {
                let weekend = try XCTUnwrap(snapshot.weekends.first)
                panelSnapshot.weekends = [RaceWeekend(id: weekend.id, year: weekend.year, name: weekend.name,
                    sessions: weekend.sessions.map { RaceSession(id: $0.id, name: $0.name, start: $0.start) })]
            }
            let store = SeasonStore(repository: PanelRepository(snapshot: panelSnapshot), clock: { now })
            await store.start()
            XCTAssertEqual(store.featured?.id, 1)
            let host = NSHostingView(rootView: NextWeekendView(store: store, preferences: preferences, coordinator: AppCoordinator()))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 386, height: 760), styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            defer { store.cancelRefresh(); window.contentView = nil; window.close() }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                host.layoutSubtreeIfNeeded()
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.width, 386, accuracy: 1)
                XCTAssertLessThanOrEqual(host.fittingSize.height, 760)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().appending(path: ".build/screenshots")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let suffix = appearance == .aqua ? "light" : "dark"
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appending(path: "menu-\(name)-\(suffix).png"))
            }
        }
    }

    private func fixture(_ parser: ISO8601DateFormatter) throws -> SeasonSnapshot {
        let values = [
            ("Practice 1", "2026-10-30T15:00:00Z", "2026-10-30T16:00:00Z"),
            ("Sprint Qualifying", "2026-10-30T18:00:00Z", "2026-10-30T19:00:00Z"),
            ("Sprint", "2026-10-31T15:00:00Z", "2026-10-31T16:00:00Z"),
            ("Qualifying", "2026-10-31T18:00:00Z", "2026-10-31T19:00:00Z"),
            ("Race", "2026-11-01T17:00:00Z", "2026-11-01T19:00:00Z")
        ]
        var snapshot = SeasonSnapshot(year: 2026)
        snapshot.weekends = [RaceWeekend(id: 1, year: 2026, name: "Fixture Grand Prix", circuit: "Test circuit", country: "Test country",
            sessions: try values.enumerated().map { index, value in
                RaceSession(id: index + 1, name: value.0, start: try XCTUnwrap(parser.date(from: value.1)), end: try XCTUnwrap(parser.date(from: value.2)))
            })]
        snapshot.scheduleUpdatedAt = parser.date(from: "2026-10-30T10:00:00Z")
        return snapshot
    }
}

private struct PanelRepository: SeasonRepository {
    let snapshot: SeasonSnapshot
    func cached(year: Int) async throws -> SeasonSnapshot? { snapshot }
    func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot { snapshot }
}
