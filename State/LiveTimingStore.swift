import Foundation
import Observation
import OSLog

@MainActor @Observable
public final class LiveTimingStore {
    public private(set) var state = LiveTimingState()
    public private(set) var isRunning = false
    @ObservationIgnored private let feed: any LiveTimingFeed
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var paused = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.murilloarturo.f1menubar", category: "LiveConnection")

    public init(feed: any LiveTimingFeed) { self.feed = feed }

    public func setVisible(_ value: Bool) {
        guard visible != value else { return }
        logger.info("Visibility=\(value) suspended=\(self.suspended) paused=\(self.paused)")
        visible = value
        if visible && !suspended && !paused { start() } else { stop() }
    }
    public func connect() { paused = false; if visible && !suspended { start() } }
    public func disconnect() { paused = true; stop() }
    public func suspend() { suspended = true; stop() }
    public func resume() { suspended = false; if visible && !paused { start() } }

    public func start() {
        guard task == nil else { return }
        generation += 1
        let token = generation
        state.phase = .connecting; state.message = nil
        isRunning = true
        task = Task { [weak self, feed] in
            await feed.run { [weak self] state in await self?.receive(state, generation: token) }
            guard let self, generation == token else { return }
            task = nil; isRunning = false
        }
    }

    public func stop() {
        generation += 1
        task?.cancel(); task = nil
        isRunning = false
        state.phase = .stopped
        state.message = nil
    }

    private func receive(_ value: LiveTimingState, generation token: Int) {
        guard generation == token, !Task.isCancelled else { return }
        if state.phase != value.phase || state.snapshot.drivers.isEmpty != value.snapshot.drivers.isEmpty {
            logger.info("Phase=\(String(describing: value.phase), privacy: .public) drivers=\(value.snapshot.drivers.count)")
        }
        state = value
    }
}
