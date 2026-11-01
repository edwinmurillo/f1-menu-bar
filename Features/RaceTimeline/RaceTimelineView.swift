import F1Core
import SwiftUI

struct RaceTimelineView: View {
    let season: SeasonStore
    let historyStore: RaceHistoryStore
    @Bindable var coordinator: AppCoordinator
    let preferences: AppPreferences
    var liveStore: LiveTimingStore? = nil
    var returnToLive: (() -> Void)? = nil
    @State private var selectedLap = 1
    @State private var highlightedDriver: String?

    private var options: [RaceHistoryRequest] {
        season.visibleSnapshot.weekends.filter { $0.hasStartedTimelineSession(at: season.now) }
            .map { RaceHistoryRequest(weekend: $0, provider: season.visibleSnapshot.provider) }
    }
    private var selectedWeekend: RaceHistoryRequest? {
        if let requested = coordinator.timelineRequest {
            if let match = options.first(where: { $0.weekend.id == requested.weekend.id && $0.weekend.year == requested.weekend.year }) { return match }
            if let date = requested.weekend.grandPrix?.start {
                let matches = options.filter { $0.weekend.year == requested.weekend.year &&
                    $0.weekend.grandPrix?.start.map { abs($0.timeIntervalSince(date)) < 12 * 3600 } == true }
                if matches.count == 1 { return matches[0] }
            }
        }
        if let featured = season.policy.featured(in: season.visibleSnapshot.weekends, now: season.now),
           let match = options.first(where: { $0.weekend.id == featured.id }) { return match }
        return options.last(where: { $0.weekend.winner != nil }) ?? options.first
    }
    private var sessions: [RaceSession] {
        (selectedWeekend?.weekend.activeSessions ?? []).filter {
            $0.start.map { $0 <= season.now } ?? ($0.isGrandPrix && selectedWeekend?.weekend.winner != nil)
        }.sorted { ($0.start ?? .distantFuture, $0.id) < ($1.start ?? .distantFuture, $1.id) }
    }
    private var selected: RaceHistoryRequest? {
        guard let weekend = selectedWeekend else { return nil }
        let requested = coordinator.timelineRequest
        let requestedSession = requested?.weekend.id == weekend.weekend.id ? sessions.first { $0.id == requested?.sessionID } : nil
        let latestStarted = sessions.last { ($0.start ?? .distantFuture) <= season.now }
        let session = requestedSession ?? latestStarted ?? sessions.first
        return RaceHistoryRequest(weekend: weekend.weekend, provider: weekend.calendarProvider,
            sessionID: session?.isGrandPrix == true && requestedSession == nil ? nil : session?.id)
    }
    private var liveHistory: RaceHistory? {
        guard let selected, let recording = liveStore?.recording else { return nil }
        return LiveRecordingHistory.make(recording, request: selected)
    }
    private var displayHistory: RaceHistory? {
        let saved = historyStore.history.flatMap { $0.request.key == selected?.key ? $0 : nil }
        if let saved, !saved.laps.isEmpty, saved.detailsComplete != false,
           liveStore?.state.snapshot.hasFreshTiming(at: season.now) != true { return saved }
        return liveHistory ?? saved
    }
    private var awaitingLiveLap: Bool {
        guard let selected, let session = selected.session, let start = session.start,
              let snapshot = liveStore?.state.snapshot, let name = snapshot.sessionName,
              name.caseInsensitiveCompare(session.name) == .orderedSame,
              snapshot.meetingName?.caseInsensitiveCompare(selected.weekend.name) == .orderedSame else { return false }
        let elapsed = season.now.timeIntervalSince(start)
        return elapsed >= -6 * 3600 && elapsed <= 24 * 3600 && liveStore?.isRunning == true
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if liveHistory == nil, let issue = historyStore.issue { IssueBanner(message: issue) }
                    if let history = displayHistory, !history.laps.isEmpty {
                        RaceHistoryContent(history: history, selectedLap: $selectedLap,
                            highlightedDriver: $highlightedDriver, loadingDetails: historyStore.isLoading && history.detailsComplete == false, chartHeight: min(460, max(320, viewport.size.height * 0.54)))
                        historyFooter(history)
                    } else { emptyState.frame(maxWidth: .infinity, minHeight: max(280, viewport.size.height - 170)) }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: selected) {
            highlightedDriver = nil; selectedLap = 1
            if let selected, selected.session?.start.map({ $0 <= season.now }) ?? true {
                await historyStore.load(selected)
                if historyStore.history?.request.key == selected.key { selectedLap = max(historyStore.history?.lastLap ?? 1, 1) }
            }
        }
        .onChange(of: historyStore.history) { old, history in
            if old?.provider != history?.provider || old?.sourceID != history?.sourceID { highlightedDriver = nil }
            if let history, history.request.key == selected?.key,
               old?.request.key != history.request.key || selectedLap == old?.lastLap || selectedLap > history.lastLap {
                selectedLap = max(history.lastLap, 1)
            }
        }
        .onChange(of: liveStore?.recording?.recordedStepCount) { old, new in
            if let history = liveHistory, new != nil,
               old == nil || selectedLap == history.laps.dropLast().last?.number || selectedLap == 1 {
                selectedLap = history.lastLap
            }
        }
        .onDisappear { historyStore.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionHeader(title: "Live timing · Session history", subtitle: "Real lap history · \(String(season.visibleSnapshot.year)) season")
                Spacer()
                if let returnToLive { Button("Go Live", action: returnToLive).buttonStyle(.borderedProminent) }
                Button {
                    if let selected { Task { await historyStore.load(selected, force: true) } }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).disabled(selected == nil || historyStore.isLoading || selected?.session?.start.map { $0 > season.now } == true)
            }
            HStack(spacing: 12) {
                Picker("Grand Prix", selection: Binding(get: { selectedWeekend?.key ?? "" }, set: { key in
                    coordinator.timelineRequest = options.first { $0.key == key }
                })) {
                    if options.isEmpty { Text("No Grands Prix").tag("") }
                    ForEach(options, id: \.key) { option in
                        Text(option.weekend.name + (option.weekend.isCancelled ? " · Cancelled" : "")).tag(option.key)
                    }
                }.pickerStyle(.menu).disabled(options.isEmpty).frame(maxWidth: 420, alignment: .leading)
                Picker("Session", selection: Binding(get: { selected?.session?.id ?? 0 }, set: { id in
                    if let weekend = selectedWeekend {
                        coordinator.timelineRequest = RaceHistoryRequest(weekend: weekend.weekend, provider: weekend.calendarProvider, sessionID: id)
                    }
                })) {
                    ForEach(sessions) { session in Text(session.name).tag(session.id) }
                }.pickerStyle(.menu).disabled(sessions.isEmpty).frame(maxWidth: 280, alignment: .leading)
                Spacer()
                if historyStore.isLoading { ProgressView().controlSize(.small); Text(historyStore.history?.laps.isEmpty == false ? "Loading details…" : "Loading history…").font(.caption).foregroundStyle(.secondary) }
                else if let history = displayHistory, !history.laps.isEmpty {
                    Label(history.sourceID.hasPrefix("live:") ? "Locally recorded live timing" : Presentation.providerName(history.provider), systemImage: "externaldrive.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let selected {
                Text([selected.weekend.circuit, Presentation.date(selected.session?.start ?? selected.weekend.firstStart,
                    format: "d MMM yyyy", zone: preferences.timeZone)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if awaitingLiveLap || liveHistory != nil, let liveStore {
                    LiveSessionClockView(store: liveStore)
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if historyStore.isLoading {
            VStack(spacing: 14) {
                ProgressView()
                Text("Loading real race history").font(.headline)
                Text("Fetching laps, positions and available timing details.").foregroundStyle(.secondary)
            }
        } else if selected == nil {
            ContentUnavailableView("No Grands Prix available", systemImage: "flag.checkered",
                description: Text("Race weekends will appear when the calendar is available."))
        } else if selected?.weekend.isCancelled == true || selected?.weekend.isMissingFromSchedule == true {
            ContentUnavailableView("No race history for this event", systemImage: "calendar.badge.exclamationmark",
                description: Text("This Grand Prix is cancelled or unavailable in the latest calendar."))
        } else if let start = selected?.session?.start, start > season.now {
            ContentUnavailableView("This session is still ahead", systemImage: "flag.checkered",
                description: Text("The timeline will appear when real lap data is published. No laps or results are simulated."))
        } else if awaitingLiveLap {
            ContentUnavailableView("Waiting for a live lap", systemImage: "dot.radiowaves.left.and.right",
                description: Text("The personal live connection is active. The timeline will grow as fresh lap timing arrives and is saved locally."))
        } else {
            ContentUnavailableView {
                Label(historyStore.issue == nil ? "No lap history published yet" : "Race history is unavailable", systemImage: "chart.xyaxis.line")
            } description: {
                Text("OpenF1 has not supplied lap history for this session, or it is temporarily unavailable. Try again later or choose another session.")
            } actions: {
                Button("Try again") { if let selected { Task { await historyStore.load(selected, force: true) } } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func historyFooter(_ history: RaceHistory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if history.sourceID.hasPrefix("live:") {
                Text("Recorded from the same personal stream as Live timing. Only timing updates observed while the app was connected are stored on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if history.detailsComplete == false {
                Text(historyStore.isLoading ? "Lap positions and times are ready. Gaps, tyres and race-control details are still loading." : "Some details have not loaded. Use Refresh to try again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(history.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Text(history.sourceID.hasPrefix("live:")
                 ? "Positions, gaps and times reflect the latest streamed snapshot recorded for each lap. Missing values remain unavailable."
                 : history.provider == .openF1
                 ? "Positions and gaps are sampled at each driver’s approximate lap boundary. Missing values remain unavailable."
                 : "Positions and times are reported by Jolpica for each completed driver lap. Missing values remain unavailable.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Updated \(Presentation.date(history.updatedAt, format: "d MMM jmm", zone: preferences.timeZone))")
                Spacer()
                Link("Data source", destination: URL(string: history.sourceID.hasPrefix("live:") ? "https://www.formula1.com/" : history.provider == .openF1 ? "https://openf1.org/docs/" : "https://api.jolpi.ca/ergast/f1/")!)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RaceHistoryContent: View {
    let history: RaceHistory
    @Binding var selectedLap: Int
    @Binding var highlightedDriver: String?
    var loadingDetails = false
    var chartHeight: CGFloat = 400
    @State private var showsChart = false
    @State private var chartTab = RaceHistoryChart.Kind.positions
    @State private var gapWindow = 10
    private var isPracticeTimeline: Bool {
        history.sourceID.hasPrefix("live:") &&
            (history.request.session?.name.localizedCaseInsensitiveContains("Practice") == true ||
             history.request.session?.name.localizedCaseInsensitiveContains("Qualifying") == true ||
             history.request.session?.name.localizedCaseInsensitiveContains("Shootout") == true)
    }

    private var lap: Int { history.laps.min { abs($0.number - selectedLap) < abs($1.number - selectedLap) }?.number ?? 1 }
    private var index: Int { history.laps.firstIndex { $0.number == lap } ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                HStack {
                    Button { selectedLap = history.laps[index - 1].number } label: {
                        Label("Previous lap", systemImage: "chevron.left")
                    }.disabled(index == 0)
                    Spacer()
                    VStack(spacing: 3) {
                        Text(isPracticeTimeline ? "Best-lap update \(lap) of \(history.lastLap)" : "Lap \(lap) of \(history.lastLap)")
                            .font(.headline).monospacedDigit()
                        Text(isPracticeTimeline ? "Practice ranking progress" : "Session progress").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selectedLap = history.laps[index + 1].number } label: {
                        Label("Next lap", systemImage: "chevron.right")
                    }.disabled(index >= history.laps.count - 1)
                }.buttonStyle(.bordered)
                Slider(value: Binding(get: { Double(lap) }, set: { value in
                    selectedLap = history.laps.min { abs(Double($0.number) - value) < abs(Double($1.number) - value) }?.number ?? 1
                }), in: 1...Double(max(2, history.lastLap)), step: 1)
                    .tint(Presentation.accent)
                    .accentColor(Presentation.accent)
                    .disabled(history.laps.count < 2)
                    .accessibilityLabel(isPracticeTimeline ? "Practice best-lap progress" : "Session lap progress")
                    .accessibilityValue(isPracticeTimeline ? "Update \(lap) of \(history.lastLap)" : "Lap \(lap) of \(history.lastLap)")
                    .frame(maxWidth: .infinity)
                HStack {
                    Text(isPracticeTimeline ? "First best time" : "Lap 1")
                    Spacer()
                    Text(isPracticeTimeline ? "\(history.lastLap) best-lap updates" : "\(history.lastLap) laps available")
                }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            DisclosureGroup("Position history", isExpanded: $showsChart) {
                VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Chart", selection: $chartTab) {
                    Text("Positions").tag(RaceHistoryChart.Kind.positions)
                    Text("Gaps").tag(RaceHistoryChart.Kind.gaps)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                if chartTab == .gaps {
                    Picker("Recent laps", selection: $gapWindow) { Text("Last 5").tag(5); Text("Last 10").tag(10) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                Spacer()
                Menu {
                    Button("All drivers") { highlightedDriver = nil }
                    ForEach(history.drivers) { driver in
                        Button(driver.name) { highlightedDriver = driver.id }
                    }
                } label: {
                    Label(history.drivers.first { $0.id == highlightedDriver }?.abbreviation ?? "All drivers", systemImage: "line.3.horizontal.decrease")
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if chartTab == .gaps && loadingDetails {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading recorded gaps…").font(.headline)
                    Text("Positions and lap times are already available.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: chartHeight)
            } else if chartTab == .gaps && !history.laps.contains(where: { $0.timings.contains { $0.position != 1 && $0.gap?.seconds != nil } }) {
                ContentUnavailableView("Gap data isn’t available", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("This source provides real lap times and positions, but no usable gap samples for this race."))
                    .frame(height: chartHeight)
            } else {
                RaceHistoryChart(history: history, selectedLap: lap, highlightedDriver: highlightedDriver,
                    kind: chartTab, gapWindow: gapWindow, selectLap: { selectedLap = $0 })
                    .frame(height: chartHeight)
            }
                }
            }
            RaceHistoryTimingTable(history: history, lap: lap, highlightedDriver: $highlightedDriver)
            raceControl
        }
    }
    private var raceControl: some View {
        let events = history.events.filter { $0.lap == lap }
        return VStack(alignment: .leading, spacing: 8) {
            if !events.isEmpty {
                Text("Race control · lap \(lap)").font(.headline)
                ForEach(events) { event in
                    Label(event.message, systemImage: "flag").font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
