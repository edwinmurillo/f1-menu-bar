import F1Core
import SwiftUI

struct RaceTimelineView: View {
    let season: SeasonStore
    let historyStore: RaceHistoryStore
    @Bindable var coordinator: AppCoordinator
    let preferences: AppPreferences
    @State private var selectedLap = 1
    @State private var highlightedDriver: String?

    private var options: [RaceHistoryRequest] {
        season.visibleSnapshot.weekends.map { RaceHistoryRequest(weekend: $0, provider: season.visibleSnapshot.provider) }
    }
    private var selected: RaceHistoryRequest? {
        if let requested = coordinator.timelineRequest {
            if let match = options.first(where: { $0.key == requested.key }) { return match }
            // Calendar fallback changes provider IDs, not the selected GP. Resolve
            // the unique scheduled race by its absolute timestamp, never join IDs.
            if let date = requested.weekend.grandPrix?.start {
                let matches = options.filter { $0.weekend.year == requested.weekend.year &&
                    $0.weekend.grandPrix?.start.map { abs($0.timeIntervalSince(date)) < 12 * 3600 } == true }
                if matches.count == 1 { return matches[0] }
            }
        }
        return options.last(where: { $0.weekend.winner != nil }) ?? options.first
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let issue = historyStore.issue { IssueBanner(message: issue) }
                    if let history = historyStore.history, history.request.key == selected?.key, !history.laps.isEmpty {
                        RaceHistoryContent(history: history, selectedLap: $selectedLap,
                            highlightedDriver: $highlightedDriver, chartHeight: min(460, max(320, viewport.size.height * 0.54)))
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
            if let selected {
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
        .onDisappear { historyStore.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SectionHeader(title: "Race timeline", subtitle: "Real lap history · \(String(season.visibleSnapshot.year)) season")
                Spacer()
                Button {
                    if let selected { Task { await historyStore.load(selected, force: true) } }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).disabled(selected == nil || historyStore.isLoading)
            }
            HStack(spacing: 12) {
                Picker("Grand Prix", selection: Binding(get: { selected?.key ?? "" }, set: { key in
                    coordinator.timelineRequest = options.first { $0.key == key }
                })) {
                    ForEach(options, id: \.key) { option in
                        Text(option.weekend.name + (option.weekend.isCancelled ? " · Cancelled" : "")).tag(option.key)
                    }
                }.pickerStyle(.menu).frame(maxWidth: 420, alignment: .leading)
                Spacer()
                if historyStore.isLoading { ProgressView().controlSize(.small); Text("Loading history…").font(.caption).foregroundStyle(.secondary) }
                else if let history = historyStore.history, !history.laps.isEmpty {
                    Label(Presentation.providerName(history.provider), systemImage: "externaldrive.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let selected {
                Text([selected.weekend.circuit, Presentation.date(selected.weekend.grandPrix?.start ?? selected.weekend.firstStart,
                    format: "d MMM yyyy", zone: preferences.timeZone)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
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
            ContentUnavailableView("Choose a Grand Prix", systemImage: "flag.checkered",
                description: Text("Race weekends will appear when the season calendar is available."))
        } else if selected?.weekend.isCancelled == true || selected?.weekend.isMissingFromSchedule == true {
            ContentUnavailableView("No race history for this event", systemImage: "calendar.badge.exclamationmark",
                description: Text("This Grand Prix is cancelled or unavailable in the latest calendar."))
        } else if let start = selected?.weekend.grandPrix?.start, start > season.now {
            ContentUnavailableView("This Grand Prix is still ahead", systemImage: "flag.checkered",
                description: Text("The timeline will appear when real lap data is published. No laps or results are simulated."))
        } else {
            ContentUnavailableView {
                Label(historyStore.issue == nil ? "No lap history published yet" : "Race history is unavailable", systemImage: "chart.xyaxis.line")
            } description: {
                Text("This provider has not supplied lap history for the selected GP, or it is temporarily unavailable. Try again later or choose another race.")
            } actions: {
                Button("Try again") { if let selected { Task { await historyStore.load(selected, force: true) } } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func historyFooter(_ history: RaceHistory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(history.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Text(history.provider == .openF1
                 ? "Positions and gaps are sampled at each driver’s approximate lap boundary. Missing values remain unavailable."
                 : "Positions and times are reported by Jolpica for each completed driver lap. Missing values remain unavailable.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Updated \(Presentation.date(history.updatedAt, format: "d MMM jmm", zone: preferences.timeZone))")
                Spacer()
                Link("Data source", destination: URL(string: history.provider == .openF1 ? "https://openf1.org/docs/" : "https://api.jolpi.ca/ergast/f1/")!)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RaceHistoryContent: View {
    let history: RaceHistory
    @Binding var selectedLap: Int
    @Binding var highlightedDriver: String?
    var chartHeight: CGFloat = 400
    @State private var chartTab = RaceHistoryChart.Kind.positions
    @State private var gapWindow = 10

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
                        Text("Lap \(lap) of \(history.lastLap)").font(.headline).monospacedDigit()
                        Text("Grand Prix progress").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selectedLap = history.laps[index + 1].number } label: {
                        Label("Next lap", systemImage: "chevron.right")
                    }.disabled(index >= history.laps.count - 1)
                }.buttonStyle(.bordered)
                Slider(value: Binding(get: { Double(lap) }, set: { value in
                    selectedLap = history.laps.min { abs(Double($0.number) - value) < abs(Double($1.number) - value) }?.number ?? 1
                }), in: 1...Double(max(2, history.lastLap)), step: 1)
                    .disabled(history.laps.count < 2)
                    .accessibilityLabel("Grand Prix lap progress")
                    .accessibilityValue("Lap \(lap) of \(history.lastLap)")
                    .frame(maxWidth: .infinity)
                HStack {
                    Text("Lap 1")
                    Spacer()
                    Text("\(history.lastLap) laps available")
                }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
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
            if chartTab == .gaps && !history.laps.contains(where: { $0.timings.contains { $0.gap?.seconds != nil } }) {
                ContentUnavailableView("Gap data isn’t available", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("This source provides real lap times and positions, but no usable gap samples for this race."))
                    .frame(height: chartHeight)
            } else {
                RaceHistoryChart(history: history, selectedLap: lap, highlightedDriver: highlightedDriver,
                    kind: chartTab, gapWindow: gapWindow, selectLap: { selectedLap = $0 })
                    .frame(height: chartHeight)
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
