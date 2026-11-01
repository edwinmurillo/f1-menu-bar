import AppKit
import SwiftUI
import XCTest
@testable import F1Core

/// Exercise the real SwiftUI/AppKit layout in an offscreen window. No app launch,
/// UI automation, live network, or screenshots are needed to catch this regression.
@MainActor final class LiveTimingLayoutTests: XCTestCase {
    func testProjectedPointsRespectSessionPositionAndRetirement() {
        XCTAssertEqual((1...11).map { LiveProjectedPoints.points(position: $0, session: "Race", retired: false) },
            [25, 18, 15, 12, 10, 8, 6, 4, 2, 1, 0])
        XCTAssertEqual((1...9).map { LiveProjectedPoints.points(position: $0, session: "Sprint", retired: false) },
            [8, 7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertNil(LiveProjectedPoints.points(position: 1, session: "Qualifying", retired: false))
        XCTAssertNil(LiveProjectedPoints.points(position: 1, session: "Sprint Qualifying", retired: false))
        XCTAssertNil(LiveProjectedPoints.points(position: 1, session: "Race", retired: true))
        XCTAssertNil(LiveProjectedPoints.points(position: nil, session: "Race", retired: false))
        XCTAssertNil(LiveProjectedPoints.points(position: 0, session: "Race", retired: false))
    }

    func testFastestLapUsesWholeFieldAndPreservesTiesAndMissingValues() throws {
        let drivers = fixture().drivers
        XCTAssertEqual(LiveFastestLap.driverIDs(in: drivers), ["2"])
        let filtered = LiveTimingFilter(driverID: "1").apply(to: drivers)
        XCTAssertFalse(LiveFastestLap.driverIDs(in: drivers).contains(try XCTUnwrap(filtered.first).id))
        XCTAssertEqual(LiveFastestLap.driverIDs(in: [drivers[0], drivers[2]]), ["1", "3"])
        XCTAssertTrue(LiveFastestLap.driverIDs(in: []).isEmpty)
        let missing = LiveDriverTiming(id: "missing", position: nil, name: "Unknown", abbreviation: "UNK",
            team: "", teamColor: nil, gap: nil, interval: nil, laps: nil, lastLap: nil, bestLap: nil,
            sectors: [], stops: nil, inPit: false, retired: false, knockedOut: false, stints: [])
        XCTAssertTrue(LiveFastestLap.driverIDs(in: [missing]).isEmpty)
    }

    func testReplayStaysPinnedAcrossUpdatesAndGoLiveFollowsLatestLap() {
        var playback = LiveLapPlayback()
        XCTAssertEqual(playback.displayedLap(latest: 12), 12)
        playback.select(7, available: [3, 6, 9, 12])
        XCTAssertEqual(playback.lap, 6, "Missing laps must snap to an observed lap")
        XCTAssertEqual(playback.displayedLap(latest: 13), 6, "New timing must not interrupt replay")
        playback.goLive()
        XCTAssertEqual(playback.displayedLap(latest: 13), 13)
        XCTAssertEqual(playback.displayedLap(latest: 14), 14)
        playback.select(1, available: [])
        XCTAssertNil(playback.lap)
    }

    func testLiveTimingLeadsSidebarAndTimelineIsMerged() {
        XCTAssertEqual(AppSection.allCases.first, .live)
        XCTAssertFalse(AppSection.allCases.map(\.rawValue).contains("timeline"))
    }

    func testFirstTimingSnapshotDoesNotMoveTheSplitViewOutsideTheWindow() async throws {
        let harness = Harness()
        addTeardownBlock { await harness.finish() }
        harness.coordinator.section = .live
        try harness.assertContentFits()
        await harness.load(snapshot: fixture())
        XCTAssertEqual(harness.live.state.snapshot.drivers.count, 22)
        try harness.assertContentFits()
    }

    func testNavigationAndSessionResetKeepContentInsideTheWindow() async throws {
        let harness = Harness()
        addTeardownBlock { await harness.finish() }
        try harness.assertContentFits()
        harness.coordinator.section = .live
        await harness.load(snapshot: fixture())
        try harness.assertContentFits()
        for section in [AppSection.drivers, .constructors, .calendar, .live] {
            harness.coordinator.section = section
            try harness.assertContentFits()
        }
        var reset = LiveTimingSnapshot()
        reset.sessionID = "next-session"
        await harness.feed.send(LiveTimingState(phase: .connected, snapshot: reset))
        try harness.assertContentFits()
    }

    func testLongErrorAndResizingDoNotEnlargeTheSplitView() async throws {
        let harness = Harness()
        addTeardownBlock { await harness.finish() }
        harness.coordinator.section = .live
        let snapshot = fixture()
        await harness.load(snapshot: snapshot)
        await harness.feed.send(LiveTimingState(phase: .reconnecting, snapshot: snapshot,
            message: String(repeating: "Connection interrupted; waiting to reconnect. ", count: 10)))
        for size in [NSSize(width: 1000, height: 720), NSSize(width: 1200, height: 900), NSSize(width: 1000, height: 720)] {
            harness.window.setContentSize(size)
            try harness.assertContentFits()
        }
    }

    func testExpandedTimingAndRaceControlUseOnePageScrollInBothAppearances() async throws {
        _ = NSApplication.shared
        let feed = LayoutFeed()
        let store = LiveTimingStore(feed: feed)
        store.start(); await feed.waitForConnection()
        var earlier = fixture(stintCount: 8)
        earlier.currentLap = 31
        await feed.send(LiveTimingState(phase: .connected, snapshot: earlier))
        await feed.send(LiveTimingState(phase: .reconnecting, snapshot: fixture(stintCount: 8),
            message: String(repeating: "Connection interrupted; waiting to reconnect. ", count: 12)))
        XCTAssertEqual(store.lapSnapshots.count, 2)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "LiveScroll-\(UUID().uuidString)")!)
        let host = NSHostingView(rootView: LiveTimingView(store: store, preferences: preferences))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 835, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        for (appearance, width) in [(NSAppearance.Name.aqua, 835), (.darkAqua, 1400)] {
            window.setContentSize(NSSize(width: width, height: 720))
            window.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            let scrolls = scrollViews(host)
            XCTAssertEqual(scrolls.count, 1, "Timing rows, errors, race control and tyre previews must share the page scroll")
            let scroll = try XCTUnwrap(scrolls.first)
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.frame.height, 22 * 64, "Timing and race-control rows must remain expanded")
            XCTAssertLessThanOrEqual(host.fittingSize.height, host.bounds.height + 1)
            XCTAssertLessThanOrEqual(document.frame.width, scroll.contentView.bounds.width + 1, "The tyre column must fit without horizontal scrolling")
            try capture(host, name: appearance == .aqua ? "live-expanded-light" : "live-expanded-dark")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView); host.layoutSubtreeIfNeeded()
            try capture(host, name: appearance == .aqua ? "live-race-control-light" : "live-race-control-dark")
            scroll.contentView.scroll(to: .zero)
        }
        store.stop(); await feed.finish(); window.contentView = nil; window.close()
    }

    func testDriverAndTeamFiltersPreserveRanksAndReconcileRosterChanges() {
        let drivers = fixture().drivers
        var filter = LiveTimingFilter(driverID: "2", team: "Team B")
        XCTAssertEqual(filter.apply(to: drivers).map(\.position), [2])
        filter.team = "Team A"; filter.reconcile(with: drivers)
        XCTAssertNil(filter.driverID, "Changing team must clear an incompatible driver filter")
        XCTAssertEqual(filter.apply(to: drivers).count, 11)
        filter.driverID = "1"
        XCTAssertEqual(filter.apply(to: drivers).map(\.id), ["1"])
        filter.reconcile(with: [])
        XCTAssertEqual(filter, LiveTimingFilter())
        XCTAssertEqual(LiveTimingFilter.teams(in: drivers), ["Team A", "Team B"])
        XCTAssertEqual(LiveTimingFilter().apply(to: drivers), drivers)
    }

    func testFullTyreHistoryModalRemainsBoundedAndScrollable() throws {
        _ = NSApplication.shared
        let driver = try XCTUnwrap(fixture(stintCount: 8).drivers.first)
        let host = NSHostingView(rootView: TyreHistorySheet(driverName: driver.name, segments: driver.tyreHistory, stints: driver.stints))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 520), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let scrolls = scrollViews(host)
        XCTAssertEqual(scrolls.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(scrolls.first?.documentView).frame.height, 8 * 55)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 521)
        try capture(host, name: "live-tyre-history-modal")
    }

    func testFourStintPreviewFitsOneLineWithoutHorizontalScrolling() throws {
        _ = NSApplication.shared
        let segments = [
            TyreHistorySegment(compound: "SOFT", completedLaps: 1),
            TyreHistorySegment(compound: "MEDIUM", completedLaps: 106),
            TyreHistorySegment(compound: "HARD", completedLaps: 999),
            TyreHistorySegment(compound: "INTERMEDIATE", completedLaps: nil)
        ]
        let host = NSHostingView(rootView: TyreHistorySummary(segments: segments, driverName: "Fixture driver"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.height, 20, "All four stints must stay on the same line")
        XCTAssertLessThanOrEqual(host.fittingSize.width, 320, "Long lap counts must fit in the tyre-history column")
        XCTAssertTrue(scrollViews(host).isEmpty)
    }

    func testTyrePreviewRevealsMoreStintsOnResizeAndHidesMoreWhenAllFit() throws {
        _ = NSApplication.shared
        let driver = try XCTUnwrap(fixture(stintCount: 8).drivers.first)
        let host = NSHostingView(rootView: TyreHistorySummary(segments: driver.tyreHistory, driverName: driver.name, stints: driver.stints)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 70), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        for width in [240, 400, 800, 240] {
            window.setContentSize(NSSize(width: width, height: 70))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.bounds.width, CGFloat(width), accuracy: 1)
            XCTAssertTrue(scrollViews(host).isEmpty)
            try capture(host, name: "tyre-preview-\(width)")
        }
    }

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
    }
    private func capture(_ host: NSView, name: String) throws {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: ".build/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appending(path: name + ".png"))
    }

    private func fixture(stintCount: Int = 1) -> LiveTimingSnapshot {
        var value = LiveTimingSnapshot()
        value.sessionID = "fixture-session"
        value.meetingName = "Fixture Grand Prix"
        value.sessionName = "Race"
        value.sessionStatus = "Started"
        value.trackStatus = "All Clear"
        value.currentLap = 32; value.totalLaps = 56
        value.airTemperature = "24"; value.trackTemperature = "36"
        value.drivers = (1...22).map { number in
            LiveDriverTiming(id: String(number), position: number, name: "Fixture Driver \(number)",
                abbreviation: "F\(number)", team: number.isMultiple(of: 2) ? "Team B" : "Team A", teamColor: "FF8000", gap: "+4.123", interval: "+1.234",
                laps: 32, lastLap: "1:21.123", bestLap: number == 2 ? "1:20.987" : "1:21.100", sectors: ["25.1", "30.2", "26.3"],
                stops: 1, inPit: false, retired: number == 4, knockedOut: false,
                stints: (0..<stintCount).map { LiveTyreStint(id: $0, compound: $0.isMultiple(of: 2) ? "MEDIUM" : "SOFT", tyreAge: $0.isMultiple(of: 3) ? 1 : $0.isMultiple(of: 2) ? 6 : 12, initialAge: 0, isNew: true) })
        }
        value.messages = (1...40).map { LiveRaceMessage(id: String($0), date: nil,
            message: "Fixture race control message \($0) with additional details that can wrap across lines.") }
        return value
    }
}

@MainActor private final class Harness {
    let feed = LayoutFeed()
    let live: LiveTimingStore
    let season = SeasonStore(repository: LayoutSeasonRepository(), clock: { Date(timeIntervalSince1970: 1_800_000_000) })
    let coordinator = AppCoordinator()
    let window: NSWindow
    let host: NSHostingView<AnyView>

    init() {
        _ = NSApplication.shared
        live = LiveTimingStore(feed: feed)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "F1LayoutTests-\(UUID().uuidString)")!)
        let root = ChampionshipWindow(store: season, liveStore: live, historyStore: RaceHistoryStore(repository: EmptyHistoryRepository()), preferences: preferences,
            coordinator: coordinator, loginItem: LoginItemController()).frame(minWidth: 1000, minHeight: 720)
        host = NSHostingView(rootView: AnyView(root))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
    }

    func load(snapshot: LiveTimingSnapshot) async {
        live.start()
        await feed.waitForConnection()
        await feed.send(LiveTimingState(phase: .connected, snapshot: snapshot))
    }

    func assertContentFits(file: StaticString = #filePath, line: UInt = #line) throws {
        // Force a layout pass after the known state publication, rather than waiting
        // a guessed amount of time for the SwiftUI transaction to render.
        host.layoutSubtreeIfNeeded()
        let split = try XCTUnwrap(findSplitView(host), file: file, line: line)
        let frame = host.convert(split.bounds, from: split)
        XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, host.bounds.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, host.bounds.maxY + 1, file: file, line: line)
        XCTAssertLessThanOrEqual(host.fittingSize.height, host.bounds.height + 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, host.bounds.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, host.bounds.maxX + 1, file: file, line: line)
    }

    func capture(name: String) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: ".build/screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appending(path: "\(name).png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }

    private func findSplitView(_ view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap { self.findSplitView($0) }.first
    }

    func finish() async {
        live.stop(); season.cancelRefresh()
        await feed.finish()
        window.contentView = nil
        window.close()
    }
}

private actor LayoutFeed: LiveTimingFeed {
    private var update: (@Sendable (LiveTimingState) async -> Void)?
    private var connectionWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?

    func run(onUpdate: @escaping @Sendable (LiveTimingState) async -> Void) async {
        update = onUpdate
        await withCheckedContinuation { continuation in
            completion = continuation
            connectionWaiters.forEach { $0.resume() }
            connectionWaiters.removeAll()
        }
    }
    func waitForConnection() async {
        if update != nil { return }
        await withCheckedContinuation { connectionWaiters.append($0) }
    }
    func send(_ value: LiveTimingState) async { await update?(value) }
    func finish() { completion?.resume(); completion = nil; update = nil }
}

private struct LayoutSeasonRepository: SeasonRepository {
    func cached(year: Int) async throws -> SeasonSnapshot? { nil }
    func refresh(year: Int, previous: SeasonSnapshot?, publish: @escaping @Sendable (SeasonSnapshot) async -> Void) async throws -> SeasonSnapshot {
        SeasonSnapshot(year: year)
    }
}

private struct EmptyHistoryRepository: RaceHistoryRepository {
    func cached(_ request: RaceHistoryRequest) async throws -> RaceHistory? { nil }
    func fetch(_ request: RaceHistoryRequest) async throws -> RaceHistory {
        RaceHistory(request: request, provider: .openF1, sourceID: "none", drivers: [], laps: [], events: [], updatedAt: Date())
    }
}
