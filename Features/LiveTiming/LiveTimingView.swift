import F1Core
import SwiftUI

struct LiveTimingView: View {
    let store: LiveTimingStore
    let preferences: AppPreferences
    var season: SeasonStore? = nil
    var historyStore: RaceHistoryStore? = nil
    var coordinator: AppCoordinator? = nil
    @State private var playback = LiveLapPlayback()
    @State private var showsPositions = false
    @State private var simulation: StandingsSimulation?
    @State private var selectedDriver: String?
    @State private var filter = LiveTimingFilter()
    @State private var showsRaceControl = true
    @State private var seenMessages: Set<String> = []
    private var request: RaceHistoryRequest? { coordinator?.timelineRequest }
    private var currentRequest: RaceHistoryRequest? {
        guard let season else { return nil }
        let weekends = season.snapshot.weekends
        guard let weekend = weekends.first(where: { $0.name.caseInsensitiveCompare(store.state.snapshot.meetingName ?? "") == .orderedSame && season.policy.isOngoing($0, now: season.now, timeZone: preferences.timeZone) })
                ?? season.policy.featured(in: weekends, now: season.now),
              season.policy.isOngoing(weekend, now: season.now, timeZone: preferences.timeZone) else { return nil }
        let started = weekend.activeSessions.filter { $0.start.map { $0 <= season.now } ?? false }.sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        guard let session = started.last else { return nil }
        if store.state.snapshot.meetingName?.caseInsensitiveCompare(weekend.name) == .orderedSame,
           store.state.snapshot.sessionName?.caseInsensitiveCompare(session.name) == .orderedSame,
           store.state.snapshot.hasFinished { return nil }
        return RaceHistoryRequest(weekend: weekend, provider: season.snapshot.provider, sessionID: session.id)
    }
    private var usesLive: Bool { request == nil || TimingHistoryPresentation.matches(request, currentRequest) }
    private var historicalRequest: RaceHistoryRequest? { usesLive ? nil : request }
    private var history: RaceHistory? {
        guard let historicalRequest else { return nil }
        if let saved = historyStore?.history, saved.request == historicalRequest { return saved }
        if let recording = store.recording { return LiveRecordingHistory.make(recording, request: historicalRequest) }
        return nil
    }
    private var messages: [LiveRaceMessage] { usesLive ? (liveSnapshotMatchesSelection ? store.state.snapshot.messages : []) : snapshot.messages }
    private var unreadCount: Int { usesLive ? messages.filter { !seenMessages.contains($0.id) }.count : 0 }
    private var canProjectPoints: Bool { usesLive || (historicalRequest?.weekend.year ?? 0) >= 2025 }
    private var simulationAction: (() -> Void)? {
        guard let season, TimingHistoryPresentation.canSimulate(state: store.state, request: request, current: currentRequest, usesLive: usesLive) else { return nil }
        return { simulation = StandingsSimulation.make(season: season.snapshot, timing: snapshot) }
    }
    private var liveSnapshotMatchesSelection: Bool {
        guard let selected = currentRequest else { return true }
        return store.state.snapshot.meetingName?.caseInsensitiveCompare(selected.weekend.name) == .orderedSame &&
            store.state.snapshot.sessionName?.caseInsensitiveCompare(selected.session?.name ?? "") == .orderedSame
    }
    private var recordedSnapshots: [Int: LiveTimingSnapshot] {
        guard liveSnapshotMatchesSelection else { return [:] }
        guard let recording = store.recording, recording.sessionID == store.state.snapshot.sessionID else { return store.lapSnapshots }
        return recording.isBestLapSession ? recording.practiceSnapshots ?? [:] : recording.laps
    }
    private var snapshot: LiveTimingSnapshot {
        if !usesLive {
            if let history { return TimingHistoryPresentation.snapshot(history, lap: playback.lap ?? history.lastLap) }
            var empty = LiveTimingSnapshot()
            empty.meetingName = request?.weekend.name; empty.sessionName = request?.session?.name
            return empty
        }
        if !liveSnapshotMatchesSelection {
            var empty = LiveTimingSnapshot()
            empty.meetingName = currentRequest?.weekend.name; empty.sessionName = currentRequest?.session?.name
            return empty
        }
        return playback.lap.flatMap { recordedSnapshots[$0] } ?? store.state.snapshot
    }
    private var positionHistory: RaceHistory? {
        if !usesLive { return history }
        guard liveSnapshotMatchesSelection else { return nil }
        guard let season, let recording = store.recording,
              recording.sessionID == store.state.snapshot.sessionID else { return nil }
        for weekend in season.snapshot.weekends {
            for session in weekend.activeSessions {
                let request = RaceHistoryRequest(weekend: weekend, provider: season.snapshot.provider, sessionID: session.id)
                if let history = LiveRecordingHistory.make(recording, request: request) { return history }
            }
        }
        return nil
    }
    private var drivers: [LiveDriverTiming] { filter.apply(to: snapshot.drivers) }
    private var selected: LiveDriverTiming? {
        drivers.first { $0.id == selectedDriver } ?? drivers.first
    }

    var body: some View {
        livePage
            .sheet(item: $simulation) { StandingsSimulationSheet(simulation: $0) }
            .onChange(of: usesLive, initial: true) { _, live in coordinator?.wantsLiveTiming = live }
            .onChange(of: request) { _, _ in
                playback.goLive(); selectedDriver = nil; filter = LiveTimingFilter(); seenMessages = []
                simulation = nil
            }
            .task(id: historicalRequest) {
                playback.goLive()
                if let historicalRequest { await historyStore?.load(historicalRequest) }
                else { historyStore?.cancel() }
            }
            .onDisappear { historyStore?.cancel() }
    }

    private var livePage: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                content(minimumHeight: viewport.size.height, availableWidth: viewport.size.width - 52)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.state.snapshot.sessionID) { _, _ in
            if usesLive { selectedDriver = nil; filter = LiveTimingFilter(); seenMessages = []; playback.goLive() }
        }
        .onChange(of: snapshot.drivers.map { $0.id + ":" + $0.team }) { _, _ in
            filter.reconcile(with: snapshot.drivers)
        }
    }

    private func content(minimumHeight: CGFloat, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Live timing", subtitle: usesLive ? "Experimental personal connection" : "Recorded session · real historical data")
            sessionSelection
            if usesLive {
                if liveSnapshotMatchesSelection { LiveTimingConnectionHeader(store: store, preferences: preferences) }
                else {
                    HStack {
                        Label("Waiting for \(currentRequest?.weekend.name ?? "current GP") · \(currentRequest?.session?.name ?? "session")", systemImage: "clock")
                        Spacer()
                        Button(store.isRunning ? "Disconnect" : "Connect") { if store.isRunning { store.disconnect() } else { store.connect() } }
                    }
                }
            }
            else {
                HStack {
                    Label("Recorded · \(snapshot.meetingName ?? "") · \(snapshot.sessionName ?? "")", systemImage: "clock")
                    Spacer()
                    Button("Refresh") { if let historicalRequest { Task { await historyStore?.load(historicalRequest, force: true) } } }
                        .disabled(historyStore?.isLoading == true)
                }.font(.headline)
                if let issue = historyStore?.issue { IssueBanner(message: issue) }
                if historyStore?.isLoading == true { ProgressView().controlSize(.small) }
            }
            replayControls
            if showsPositions {
                if let history = positionHistory {
                    RaceHistoryChart(history: history, selectedLap: playback.lap ?? history.lastLap,
                        highlightedDriver: selectedDriver, kind: .positions, gapWindow: 10,
                        selectLap: { playback.select(Double($0), available: availableLaps) }).frame(height: 320)
                } else {
                    Text("Position history will appear as session laps are recorded.").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Timing").font(.headline)
                Spacer()
            }
            let sideBySide = showsRaceControl && availableWidth >= 1120
            let timingWidth = sideBySide ? availableWidth - 336 : availableWidth
            if sideBySide {
                HStack(alignment: .top, spacing: 16) {
                    timingPanel(timingWidth: timingWidth, inlineRaceControl: false).frame(width: timingWidth)
                    VStack(alignment: .leading, spacing: 16) {
                        raceControlToggle.frame(height: 28)
                        raceControl
                    }.frame(width: 320)
                }
            } else {
                timingPanel(timingWidth: timingWidth, inlineRaceControl: true)
                if showsRaceControl { raceControl }
            }
            if !usesLive, let history {
                ForEach(history.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                Text("Historical data may omit tyre, pit or interval values.").font(.caption).foregroundStyle(.secondary)
            }
            if canProjectPoints && (snapshot.sessionName?.lowercased() == "race" || snapshot.sessionName?.lowercased() == "sprint") {
                Text("* Projected points for a full-distance finish at this position; final awards may differ.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sourceAndWeather }
                VStack(alignment: .leading, spacing: 8) { sourceAndWeather }
            }.font(.caption)
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
    }

    private var availableLaps: [Int] { usesLive ? recordedSnapshots.keys.sorted() : history?.laps.map(\.number) ?? [] }

    @ViewBuilder private var sessionSelection: some View {
        if let season, let coordinator {
            let calendar = request?.weekend.year == season.visibleSnapshot.year ? season.visibleSnapshot : season.snapshot
            let options = calendar.weekends.filter { $0.hasStartedTimelineSession(at: season.now) }
            let weekend = request?.weekend ?? currentRequest?.weekend
            HStack(spacing: 12) {
                Picker("Grand Prix", selection: Binding(get: { weekend?.id ?? 0 }, set: { id in
                    if let picked = options.first(where: { $0.id == id }) {
                        let latest = picked.activeSessions.filter { $0.start.map { $0 <= season.now } ?? ($0.isGrandPrix && picked.winner != nil) }.last
                        coordinator.timelineRequest = RaceHistoryRequest(weekend: picked, provider: calendar.provider, sessionID: latest?.id)
                    }
                })) {
                    if weekend == nil { Text("Current session").tag(0) }
                    ForEach(options) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 400)
                if let weekend {
                    let sessions = weekend.activeSessions.filter { $0.start.map { $0 <= season.now } ?? ($0.isGrandPrix && weekend.winner != nil) }
                    Picker("Session", selection: Binding(get: { request?.session?.id ?? currentRequest?.session?.id ?? 0 }, set: { id in
                        coordinator.timelineRequest = RaceHistoryRequest(weekend: weekend, provider: request?.calendarProvider ?? season.snapshot.provider, sessionID: id)
                    })) {
                        ForEach(sessions) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 240)
                }
                Spacer(minLength: 0)
            }.pickerStyle(.menu)
        }
    }

    private var raceControlToggle: some View {
        Button {
            showsRaceControl.toggle()
            if showsRaceControl { seenMessages.formUnion(messages.map(\.id)) }
        } label: {
            HStack(spacing: 6) {
                if showsRaceControl { Image(systemName: "chevron.right") }
                Label("Race Control", systemImage: "flag.checkered")
                if unreadCount > 0 {
                    Text("\(unreadCount)").font(.caption.bold()).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.blue, in: Capsule()).foregroundStyle(.white)
                        .accessibilityLabel("\(unreadCount) new race control messages")
                }
            }
        }
        .help(showsRaceControl ? "Hide Race Control" : "Show Race Control")
        .accessibilityLabel(showsRaceControl ? "Hide Race Control" : "Show Race Control")
    }

    private var replayControls: some View {
        let steps = availableLaps
        let current = playback.lap ?? steps.last ?? store.state.snapshot.currentLap ?? 1
        let bestLapSession = usesLive ? store.recording?.isBestLapSession == true : history?.sourceID.hasPrefix("live:") == true && ["practice", "qualifying", "shootout"].contains { snapshot.sessionName?.lowercased().contains($0) == true }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if let index = steps.firstIndex(of: current), index > 0 { playback.select(Double(steps[index - 1]), available: steps) }
                } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(steps.firstIndex(of: current).map { $0 == 0 } ?? true)
                Text(!usesLive ? "Recorded · \(bestLapSession ? "Update" : "Lap") \(current)" : playback.lap == nil ? "Following live timing" : "Replay · \(bestLapSession ? "Update" : "Lap") \(current)")
                    .font(.headline).monospacedDigit()
                Spacer()
                Button {
                    if let index = steps.firstIndex(of: current), index + 1 < steps.count { playback.select(Double(steps[index + 1]), available: steps) }
                } label: { Label("Next", systemImage: "chevron.right") }
                    .disabled(steps.firstIndex(of: current).map { $0 + 1 >= steps.count } ?? true)
                Button("Go Live") { playback.goLive() }
                    .buttonStyle(.borderedProminent).disabled(!usesLive || playback.lap == nil)
                    .help(usesLive ? "Return to the current lap" : "Live is only available for the current ongoing session")
            }
            Slider(value: Binding(get: { Double(current) }, set: { value in
                playback.select(value, available: steps)
            }), in: Double(steps.first ?? 1)...Double(max((steps.first ?? 1) + 1, steps.last ?? 2)), step: 1)
                .tint(Presentation.accent)
                    .accentColor(Presentation.accent)
                .disabled(steps.count < 2)
                .accessibilityLabel(bestLapSession ? "Recorded best-lap updates" : "Recorded session laps")
            HStack {
                Button(showsPositions ? "Hide position history" : "Show position history") { showsPositions.toggle() }
                Text(steps.first.map { "\(bestLapSession ? "Update" : "Lap") \($0)" } ?? "Waiting for recorded laps")
                Spacer()
                Text(steps.last.map { "Latest: \($0)" } ?? "")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func timingPanel(timingWidth: CGFloat, inlineRaceControl: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if snapshot.drivers.isEmpty {
                if inlineRaceControl { raceControlToggle }
                Spacer(minLength: 24)
                if usesLive {
                    LiveTimingPlaceholder(phase: store.state.phase, isRunning: store.isRunning).frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("No recorded laps available", systemImage: "clock", description: Text("This session's provider has not published lap data yet."))
                }
                Spacer(minLength: 24)
            } else {
                HStack(spacing: 12) {
                    filters
                    if inlineRaceControl { raceControlToggle }
                }
                if drivers.isEmpty {
                    ContentUnavailableView {
                        Label("No matching drivers", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Change the driver or team filter to see timing rows.")
                    } actions: {
                        Button("Clear filters") { filter = LiveTimingFilter() }
                    }
                } else {
                    LiveTimingRows(drivers: drivers, selectedDriver: selected?.id, select: { selectedDriver = $0 }, availableWidth: timingWidth, fastestDriverIDs: LiveFastestLap.driverIDs(in: snapshot.drivers), sessionName: snapshot.sessionName,
                        simulate: simulationAction, projectedPointsEnabled: canProjectPoints)
                    if let driver = selected { driverDetail(driver) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var raceControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                if usesLive { Button("Mark read") { seenMessages.formUnion(messages.map(\.id)) }
                    .disabled(unreadCount == 0) }
            }
            if messages.isEmpty {
                Text(usesLive ? "Waiting for race control messages…" : "No recorded race control messages for this lap.").foregroundStyle(.secondary)
            }
            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(message.date.map { Presentation.date($0, format: "jmmss", zone: preferences.timeZone) } ?? "—")
                            .foregroundStyle(.secondary).monospacedDigit()
                        if usesLive && !seenMessages.contains(message.id) {
                            Text("NEW").font(.caption2.bold()).foregroundStyle(.blue)
                        }
                    }
                    Text(message.message).fixedSize(horizontal: false, vertical: true)
                }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
        }
        .padding(14).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var filters: some View {
        HStack(spacing: 14) {
            Picker("Team", selection: Binding(get: { filter.team }, set: { team in
                filter.team = team; filter.reconcile(with: snapshot.drivers)
            })) {
                Text("All teams").tag(String?.none)
                ForEach(LiveTimingFilter.teams(in: snapshot.drivers), id: \.self) { team in
                    Text(team.isEmpty ? "Unknown team" : team).tag(Optional(team))
                }
            }.frame(maxWidth: 260)
            Picker("Driver", selection: $filter.driverID) {
                Text("All drivers").tag(String?.none)
                ForEach(snapshot.drivers.filter { filter.team == nil || $0.team == filter.team }) { driver in
                    Text(driver.name).tag(Optional(driver.id))
                }
            }.frame(maxWidth: 280)
            Text("\(drivers.count) of \(snapshot.drivers.count)").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Clear filters") { filter = LiveTimingFilter() }
                .disabled(filter == LiveTimingFilter())
        }.pickerStyle(.menu)
    }

    @ViewBuilder private var sourceAndWeather: some View {
        Text(usesLive ? "Experimental · Direct F1 timing · Provisional data" : "Recorded · \(history.map { Presentation.providerName($0.provider) } ?? "Historical provider") · Missing data stays unavailable").foregroundStyle(.secondary)
        if let air = snapshot.airTemperature { Text("Air \(air)°C") }
        if let track = snapshot.trackTemperature { Text("Track \(track)°C") }
        Link("Official live timing", destination: URL(string: "https://www.formula1.com/en/timing/f1-live")!)
    }

    private func driverDetail(_ driver: LiveDriverTiming) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(driver.name).fontWeight(.semibold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), alignment: .leading)], alignment: .leading, spacing: 10) {
                Text("Ahead \(driver.interval ?? "—")")
                Text("Best \(driver.bestLap ?? "—")")
                ForEach(Array(driver.sectors.enumerated()), id: \.offset) { index, time in
                    Text("Sector \(index + 1)  \(time)")
                }
            }.font(.caption).monospacedDigit()
            Text("Tyre history").font(.caption).foregroundStyle(.secondary)
            TyreHistorySummary(segments: driver.tyreHistory, driverName: driver.name, stints: driver.stints)
            Text("Tyre-history lap counts show laps driven on each set. Pit counts are reported by the feed.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
