import AppKit
import SwiftUI
import XCTest
@testable import F1Core

/// Exercise the real SwiftUI/AppKit layout in an offscreen window. No app launch,
/// UI automation, live network, or screenshots are needed to catch this regression.
@MainActor final class LiveTimingLayoutTests: XCTestCase {
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
        for section in [AppSection.drivers, .constructors, .calendar, .live, .timeline] {
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

    private func fixture() -> LiveTimingSnapshot {
        var value = LiveTimingSnapshot()
        value.sessionID = "fixture-session"
        value.meetingName = "Fixture Grand Prix"
        value.sessionName = "Race"
        value.sessionStatus = "Started"
        value.currentLap = 32; value.totalLaps = 56
        value.airTemperature = "24"; value.trackTemperature = "36"
        value.drivers = (1...22).map { number in
            LiveDriverTiming(id: String(number), position: number, name: "Fixture Driver \(number)",
                abbreviation: "F\(number)", team: "Fixture Team", teamColor: "FF8000", gap: "+4.123", interval: "+1.234",
                laps: 32, lastLap: "1:21.123", bestLap: "1:20.987", sectors: ["25.1", "30.2", "26.3"],
                stops: 1, inPit: false, retired: false, knockedOut: false,
                stints: [LiveTyreStint(id: 0, compound: "MEDIUM", tyreAge: 12, initialAge: 0, isNew: true)])
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
