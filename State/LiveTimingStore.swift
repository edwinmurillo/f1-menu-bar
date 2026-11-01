import Foundation
import Observation
import OSLog

@MainActor @Observable
public final class LiveTimingStore {
    public private(set) var state = LiveTimingState()
    public private(set) var isRunning = false
    public private(set) var lapSnapshots: [Int: LiveTimingSnapshot] = [:]
    public private(set) var recording: LiveSessionRecording?
    public private(set) var observedLapStartedAt: Date?
    public private(set) var observedLap: Int?
    @ObservationIgnored private let feed: any LiveTimingFeed
    @ObservationIgnored private let archive: LiveLapArchive?
    @ObservationIgnored private var archiveSequence = 0
    @ObservationIgnored private var lastArchivedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var loggedSessionID: String?
    @ObservationIgnored private let logger = Logger(subsystem: "com.murilloarturo.f1menubar", category: "LiveConnection")

    public init(feed: any LiveTimingFeed, archive: LiveLapArchive? = nil) {
        self.feed = feed; self.archive = archive
        if let archive {
            Task { [weak self] in
                do {
                    if let saved = try await archive.latest(), self?.recording == nil { self?.recording = saved }
                } catch { self?.logger.error("Saved live recording could not be read: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

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
        persistRecording(force: true)
        generation += 1
        task?.cancel(); task = nil
        isRunning = false
        state.phase = .stopped
        state.message = nil
        observedLapStartedAt = nil
        observedLap = nil
    }

    private func receive(_ value: LiveTimingState, generation token: Int) {
        guard generation == token, !Task.isCancelled else { return }
        let previous = state.snapshot
        if state.phase != value.phase || state.snapshot.drivers.isEmpty != value.snapshot.drivers.isEmpty {
            logger.info("Phase=\(String(describing: value.phase), privacy: .public) drivers=\(value.snapshot.drivers.count)")
        }
        state = value
        let snapshot = value.snapshot
        // SessionInfo can arrive before the lap count or roster. Clear history as
        // soon as a different identity is known, including a non-Race session.
        if let sessionID = snapshot.sessionID, loggedSessionID != sessionID {
            loggedSessionID = sessionID
            lapSnapshots = [:]
            observedLapStartedAt = nil
            observedLap = nil
            if recording?.sessionID != sessionID {
                persistRecording(force: true)
                recording = nil; lastArchivedAt = nil
            }
        }
        if snapshot.sessionID != nil, snapshot.sessionID == previous.sessionID, let lap = snapshot.currentLap,
           lap != observedLap, let precedingLap = previous.currentLap, lap == precedingLap + 1,
           let previousReceipt = previous.receivedAt, let receipt = snapshot.receivedAt,
           (0...5).contains(receipt.timeIntervalSince(previousReceipt)) {
            observedLap = lap
            observedLapStartedAt = receipt
        } else if let lap = snapshot.currentLap, let observedLap, lap != observedLap {
            self.observedLap = nil
            observedLapStartedAt = nil
        }
        if snapshot.sessionName == "Race", let sessionID = snapshot.sessionID,
           let lap = snapshot.currentLap, (1...200).contains(lap), !snapshot.drivers.isEmpty {
            guard loggedSessionID == sessionID else { return }
            lapSnapshots[lap] = snapshot
        }
        if let sessionID = snapshot.sessionID, let name = snapshot.sessionName,
           let meeting = snapshot.meetingName, !snapshot.drivers.isEmpty,
           value.phase == .connected, snapshot.hasFreshTiming(at: snapshot.receivedAt ?? Date()) {
            if recording?.sessionID != sessionID {
                recording = LiveSessionRecording(sessionID: sessionID, meetingName: meeting,
                    sessionName: name, updatedAt: snapshot.receivedAt ?? Date())
            }
            let before = recording?.updatedAt
            recording?.record(snapshot, at: snapshot.receivedAt ?? Date())
            if let recording, recording.recordedStepCount > 0,
               (!recording.isBestLapSession || recording.updatedAt != before) {
                persistRecording()
            }
        }
    }

    private func persistRecording(force: Bool = false) {
        guard let archive, let recording, recording.recordedStepCount > 0 else { return }
        if !force, let lastArchivedAt, recording.updatedAt.timeIntervalSince(lastArchivedAt) < 5 { return }
        lastArchivedAt = recording.updatedAt
        archiveSequence += 1
        let sequence = archiveSequence
        Task { [logger] in
            do { try await archive.save(recording, sequence: sequence) }
            catch { logger.error("Live recording could not be saved: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
