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
    @State private var browsingSessions = false
    @State private var selectedDriver: String?
    @State private var filter = LiveTimingFilter()
    @State private var showsRaceControl = true
    @State private var seenMessages: Set<String> = []
    private var unreadCount: Int { store.state.snapshot.messages.filter { !seenMessages.contains($0.id) }.count }
    private var recordedSnapshots: [Int: LiveTimingSnapshot] {
        guard let recording = store.recording, recording.sessionID == store.state.snapshot.sessionID else { return store.lapSnapshots }
        return recording.isBestLapSession ? recording.practiceSnapshots ?? [:] : recording.laps
    }
    private var snapshot: LiveTimingSnapshot { playback.lap.flatMap { recordedSnapshots[$0] } ?? store.state.snapshot }
    private var positionHistory: RaceHistory? {
        guard let season, let recording = store.recording,
              recording.sessionID == store.state.snapshot.sessionID else { return nil }
        for weekend in season.visibleSnapshot.weekends {
            for session in weekend.activeSessions {
                let request = RaceHistoryRequest(weekend: weekend, provider: season.visibleSnapshot.provider, sessionID: session.id)
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
        Group {
            if browsingSessions, let season, let historyStore, let coordinator {
                RaceTimelineView(season: season, historyStore: historyStore, coordinator: coordinator,
                    preferences: preferences, liveStore: store, returnToLive: {
                        browsingSessions = false; playback.goLive(); coordinator.timelineRequest = nil
                    })
            } else { livePage }
        }
        .sheet(item: $simulation) { StandingsSimulationSheet(simulation: $0) }
        .onAppear { browsingSessions = coordinator?.timelineRequest != nil }
        .onChange(of: coordinator?.timelineRequest) { _, request in
            if request != nil { browsingSessions = true }
        }
    }

    private var livePage: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                content(minimumHeight: viewport.size.height, availableWidth: viewport.size.width - 52)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.state.snapshot.sessionID) { _, _ in
            selectedDriver = nil; filter = LiveTimingFilter(); seenMessages = []; playback.goLive()
        }
        .onChange(of: snapshot.drivers.map { $0.id + ":" + $0.team }) { _, _ in
            filter.reconcile(with: snapshot.drivers)
        }
    }

    private func content(minimumHeight: CGFloat, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Live timing", subtitle: "Experimental personal connection")
            LiveTimingConnectionHeader(store: store, preferences: preferences)
            replayControls
            if showsPositions {
                if let history = positionHistory {
                    RaceHistoryChart(history: history, selectedLap: playback.lap ?? history.lastLap,
                        highlightedDriver: selectedDriver, kind: .positions, gapWindow: 10,
                        selectLap: { playback.select(Double($0), available: Array(recordedSnapshots.keys)) }).frame(height: 320)
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
            if snapshot.sessionName?.lowercased() == "race" || snapshot.sessionName?.lowercased() == "sprint" {
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

    private var raceControlToggle: some View {
        Button {
            showsRaceControl.toggle()
            if showsRaceControl { seenMessages.formUnion(store.state.snapshot.messages.map(\.id)) }
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
        let steps = recordedSnapshots.keys.sorted()
        let current = playback.lap ?? steps.last ?? store.state.snapshot.currentLap ?? 1
        let bestLapSession = store.recording?.isBestLapSession == true
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(playback.lap == nil ? "Following live timing" : "Replay · \(bestLapSession ? "Update" : "Lap") \(current)")
                    .font(.headline).monospacedDigit()
                Spacer()
                Button("Go Live") { playback.goLive() }
                    .buttonStyle(.borderedProminent).disabled(playback.lap == nil)
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
                LiveTimingPlaceholder(phase: store.state.phase, isRunning: store.isRunning)
                    .frame(maxWidth: .infinity)
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
                        simulate: season.map { season in { simulation = StandingsSimulation.make(season: season.snapshot, timing: snapshot) } })
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
                Button("Mark read") { seenMessages.formUnion(store.state.snapshot.messages.map(\.id)) }
                    .disabled(unreadCount == 0)
            }
            if store.state.snapshot.messages.isEmpty {
                Text("Waiting for race control messages…").foregroundStyle(.secondary)
            }
            ForEach(store.state.snapshot.messages) { message in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(message.date.map { Presentation.date($0, format: "jmmss", zone: preferences.timeZone) } ?? "—")
                            .foregroundStyle(.secondary).monospacedDigit()
                        if !seenMessages.contains(message.id) {
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
        Text("Experimental · Direct F1 timing · Provisional data").foregroundStyle(.secondary)
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
