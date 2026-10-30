import F1Core
import SwiftUI

/// Unobserved laps are a local fixture. Observed laps keep their F1 timing positions.
struct TimelineRace {
    struct Driver: Identifiable {
        let timing: LiveDriverTiming
        let color: Color
        let retirementLap: Int?
        var positions: [Int?]
        var id: String { timing.id }
        var finish: Int? { positions.last ?? nil }
    }

    let laps = 56
    let mockCautionLaps = [2...3, 50...52]
    let mockSafetyCarLaps = [25...28]
    let mockRedFlagLaps = [42]
    let mockRetirementLaps = ["BOT": 48, "COL": 35, "BEA": 24]
    var drivers: [Driver]

    func activeCount(at lap: Int) -> Int {
        drivers.filter { $0.positions[lap - 1] != nil }.count
    }

    var topTenDrivers: [Driver] {
        Array(drivers.sorted {
            ($0.timing.position ?? .max, Int($0.id) ?? .max) <
            ($1.timing.position ?? .max, Int($1.id) ?? .max)
        }.prefix(10))
    }

    static func mockGapSeconds(lap: Int, position: Int, finalGap: String?, finalPosition: Int?) -> Double {
        if position == 1 { return 0 }
        let ordinaryGap = Double(position - 1) * 1.8
        guard lap >= 40 else { return ordinaryGap }
        let cleaned = finalGap?.trimmingCharacters(in: CharacterSet(charactersIn: "+s ")) ?? ""
        let finishGap = Double(cleaned) ?? Double(max((finalPosition ?? position) - 1, 0)) * 1.8
        let openingGap = finishGap == 0 ? ordinaryGap * 0.25 : finishGap * 0.25
        if lap < 47 {
            let blend = min(1, Double(lap - 40) / 6)
            return ordinaryGap + (openingGap - ordinaryGap) * blend
        }
        let progress = Double(min(lap, 56) - 47) / 9
        return openingGap + (finishGap - openingGap) * progress
    }

    init(snapshot: LiveTimingSnapshot, observedLaps: [Int: LiveTimingSnapshot], seed: UInt64) {
        let palette = ["55D6C2", "E63946", "446BFF", "FF9F34", "E5D74B", "E889B2", "4BAFD2"]
        let roster = snapshot.drivers.sorted {
            ($0.position ?? .max, Int($0.id) ?? .max) < ($1.position ?? .max, Int($1.id) ?? .max)
        }
        drivers = roster.enumerated().map { index, timing in
            Driver(timing: timing,
                   color: Presentation.color(hex: timing.teamColor ?? palette[index % palette.count]),
                   retirementLap: ["BOT": 48, "COL": 35, "BEA": 24][timing.abbreviation],
                   positions: Array(repeating: nil, count: 56))
        }
        guard drivers.count > 1 else { return }

        // Build backwards from the real finishers. A retiree rejoins the mock order
        // at their last completed lap, in its last active position, then is absent
        // from every later lap. The running positions stay contiguous.
        var order = drivers.indices.filter { drivers[$0].retirementLap == nil }
        var random = SeededRandom(seed: seed)
        for lap in stride(from: laps, through: 1, by: -1) {
            if order.count > 1 && lap < 52 && !mockCautionLaps.contains(where: { $0.contains(lap) }) &&
               !mockSafetyCarLaps.contains(where: { $0.contains(lap) }) {
                for _ in 0..<random.next(upperBound: 4) {
                    let index = random.next(upperBound: order.count - 1)
                    order.swapAt(index, index + 1)
                }
            }
            if let retiring = drivers.indices.first(where: { drivers[$0].retirementLap == lap }) {
                order.append(retiring)
            }
            for (position, driverIndex) in order.enumerated() {
                drivers[driverIndex].positions[lap - 1] = position + 1
            }
        }
        for (lap, observed) in observedLaps where (1...laps).contains(lap) && observed.sessionID == snapshot.sessionID {
            let positions = Dictionary(uniqueKeysWithValues: observed.drivers.map { ($0.id, $0.position) })
            for index in drivers.indices {
                if let retirement = drivers[index].retirementLap, lap > retirement { continue }
                if let actual = positions[drivers[index].id] {
                    if let actual, (1...activeCount(at: lap)).contains(actual) {
                        drivers[index].positions[lap - 1] = actual
                    }
                }
            }
        }
        if snapshot.currentLap == laps {
            for index in drivers.indices {
                if drivers[index].retirementLap == nil {
                    drivers[index].positions[laps - 1] = drivers[index].timing.position
                }
            }
        }
    }
}

private enum ChartEventMarker {
    static func pill(context: GraphicsContext, x: CGFloat, y: CGFloat,
                     title: String, color: Color) {
        let width: CGFloat = title == "VSC" ? 38 : 30
        let shape = Path(roundedRect: CGRect(x: x - width / 2, y: y - 9,
                                             width: width, height: 18), cornerRadius: 9)
        context.fill(shape, with: .color(color.opacity(0.18)))
        context.stroke(shape, with: .color(color), lineWidth: 1.2)
        context.draw(Text(title).font(.system(size: 10, weight: .bold))
            .foregroundStyle(color), at: CGPoint(x: x, y: y))
    }

    static func redFlag(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        context.draw(Text("🚩").font(.system(size: 16)), at: CGPoint(x: x, y: y))
    }
}

private struct GapTrendChart: View {
    private struct Sample {
        let lap: Int
        let gaps: [String: Double]
    }

    let race: TimelineRace
    let snapshots: [Int: LiveTimingSnapshot]
    let currentSnapshot: LiveTimingSnapshot
    let selectedLap: Int
    let window: Int
    let seed: UInt64
    @Binding var highlightedDriver: String?
    let selectLap: (Int) -> Void

    private var samples: [Sample] {
        (max(1, selectedLap - window + 1)...selectedLap).map { lap in
            let observed = snapshots[lap] ?? (lap == currentSnapshot.currentLap ? currentSnapshot : nil)
            let gaps = race.topTenDrivers.reduce(into: [String: Double]()) { result, driver in
                let row = TimelineLapRow(driver: driver, lap: lap, observed: observed, seed: seed)
                if let gap = row.gapSeconds { result[driver.id] = gap }
            }
            return Sample(lap: lap, gaps: gaps)
        }
    }

    var body: some View {
        let data = samples
        GeometryReader { geometry in
            Canvas { context, size in
                draw(context: context, size: size, samples: data)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                let legendLeft = geometry.size.width - 116
                if point.x >= legendLeft {
                    let row = Int((point.y - 35) / rowHeight(for: geometry.size.height))
                    let drivers = orderedDrivers
                    if point.y >= 35, drivers.indices.contains(row) {
                        let id = drivers[row].id
                        highlightedDriver = highlightedDriver == id ? nil : id
                    }
                } else if let first = data.first, let last = data.last {
                    let left: CGFloat = 54
                    let right = max(left + 1, legendLeft - 20)
                    let fraction = min(1, max(0, (point.x - left) / (right - left)))
                    selectLap(first.lap + Int((Double(last.lap - first.lap) * Double(fraction)).rounded()))
                }
            }
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Gap to leader for the top \(race.topTenDrivers.count) drivers through lap \(selectedLap), over \(data.count) laps. Select a driver in the legend or a lap on the chart.")
    }

    private var orderedDrivers: [TimelineRace.Driver] {
        race.topTenDrivers.sorted {
            ($0.positions[selectedLap - 1] ?? .max, $0.timing.name) <
            ($1.positions[selectedLap - 1] ?? .max, $1.timing.name)
        }
    }

    private var activeHighlight: String? {
        race.topTenDrivers.contains { $0.id == highlightedDriver } ? highlightedDriver : nil
    }

    private func rowHeight(for height: CGFloat) -> CGFloat {
        (height - 65) / CGFloat(max(race.topTenDrivers.count, 1))
    }

    private func draw(context: GraphicsContext, size: CGSize, samples: [Sample]) {
        guard let first = samples.first, let last = samples.last else { return }
        let left: CGFloat = 54
        let right = max(left + 1, size.width - 136)
        let top: CGFloat = 35
        let bottom = size.height - 66
        let maxGap = max(5, (samples.flatMap { $0.gaps.values }.max() ?? 0).rounded(.up))
        let x: (Int) -> CGFloat = { lap in
            left + CGFloat(lap - first.lap) / CGFloat(max(last.lap - first.lap, 1)) * (right - left)
        }
        let y: (Double) -> CGFloat = { gap in
            top + CGFloat(gap / maxGap) * (bottom - top)
        }

        context.draw(Text("GAP TO LEADER · SECONDS BEHIND")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75)), at: CGPoint(x: left, y: 16), anchor: .leading)
        for tick in 0...4 {
            let seconds = maxGap * Double(tick) / 4
            var line = Path()
            line.move(to: CGPoint(x: left, y: y(seconds)))
            line.addLine(to: CGPoint(x: right, y: y(seconds)))
            context.stroke(line, with: .color(.white.opacity(tick == 0 ? 0.35 : 0.11)), lineWidth: 1)
            context.draw(Text(tick == 0 ? "0" : String(format: "−%.0f", seconds)).font(.caption2)
                .foregroundStyle(.white.opacity(0.65)),
                at: CGPoint(x: left - 8, y: y(seconds)), anchor: .trailing)
        }
        let tickLaps = samples.count <= 10 ? samples.map(\.lap) :
            samples.map(\.lap).filter { $0 == first.lap || $0 == last.lap || $0.isMultiple(of: 5) }
        for lap in tickLaps {
            var line = Path()
            line.move(to: CGPoint(x: x(lap), y: top))
            line.addLine(to: CGPoint(x: x(lap), y: bottom))
            context.stroke(line, with: .color(.white.opacity(0.07)), lineWidth: 1)
            context.draw(Text(String(lap)).font(.caption2).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: x(lap), y: bottom + 15))
        }
        for interval in race.mockCautionLaps {
            let start = max(first.lap, interval.lowerBound)
            let end = min(last.lap, interval.upperBound)
            if start <= end {
                context.fill(Path(CGRect(x: x(start), y: top,
                                         width: max(5, x(end) - x(start)), height: bottom - top)),
                             with: .color(.orange.opacity(0.15)))
            }
        }
        for interval in race.mockSafetyCarLaps {
            let start = max(first.lap, interval.lowerBound)
            let end = min(last.lap, interval.upperBound)
            if start <= end {
                context.fill(Path(CGRect(x: x(start), y: top,
                                         width: max(5, x(end) - x(start)), height: bottom - top)),
                             with: .color(.yellow.opacity(0.24)))
            }
        }
        for driver in race.topTenDrivers {
            var path = Path()
            var connected = false
            for sample in samples {
                guard let gap = sample.gaps[driver.id] else { connected = false; continue }
                let point = CGPoint(x: x(sample.lap), y: y(gap))
                if connected { path.addLine(to: point) } else { path.move(to: point) }
                connected = true
            }
            let faded = activeHighlight != nil && activeHighlight != driver.id
            context.stroke(path, with: .color(driver.color.opacity(faded ? 0.12 : 0.88)),
                           style: StrokeStyle(lineWidth: faded ? 1 : activeHighlight == driver.id ? 3 : 1.7,
                                              lineCap: .round, lineJoin: .round))
            if let gap = last.gaps[driver.id] {
                context.fill(Path(ellipseIn: CGRect(x: x(last.lap) - 3, y: y(gap) - 3,
                                                  width: 6, height: 6)),
                             with: .color(driver.color.opacity(faded ? 0.25 : 1)))
            }
        }
        for lap in race.mockRedFlagLaps where (first.lap...last.lap).contains(lap) {
            var marker = Path()
            marker.move(to: CGPoint(x: x(lap), y: top))
            marker.addLine(to: CGPoint(x: x(lap), y: bottom))
            context.stroke(marker, with: .color(.red), lineWidth: 2.5)
            ChartEventMarker.redFlag(context: context, x: x(lap), y: bottom + 36)
        }
        for interval in race.mockSafetyCarLaps where interval.overlaps(first.lap...last.lap) {
            ChartEventMarker.pill(context: context, x: x(max(first.lap, interval.lowerBound)),
                                  y: bottom + 36, title: "SC", color: .yellow)
        }
        for interval in race.mockCautionLaps where interval.overlaps(first.lap...last.lap) {
            ChartEventMarker.pill(context: context, x: x(max(first.lap, interval.lowerBound)),
                                  y: bottom + 36, title: "VSC", color: .orange)
        }
        context.draw(Text("Lap").font(.caption).foregroundStyle(.white.opacity(0.75)),
                     at: CGPoint(x: (left + right) / 2, y: size.height - 10))
        let legendLeft = size.width - 116
        context.draw(Text("LAP \(selectedLap)").font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75)),
            at: CGPoint(x: legendLeft, y: 16), anchor: .leading)
        for (index, driver) in orderedDrivers.enumerated() {
            let rowY = top + (CGFloat(index) + 0.5) * rowHeight(for: size.height)
            guard rowY < bottom else { break }
            let faded = activeHighlight != nil && activeHighlight != driver.id
            context.fill(Path(ellipseIn: CGRect(x: legendLeft, y: rowY - 3, width: 6, height: 6)),
                         with: .color(driver.color.opacity(faded ? 0.25 : 1)))
            context.draw(Text(driver.timing.abbreviation).font(.system(size: 10, weight: .medium))
                .foregroundStyle(driver.color.opacity(faded ? 0.3 : 1)),
                at: CGPoint(x: legendLeft + 11, y: rowY), anchor: .leading)
            let label = last.gaps[driver.id].map { String(format: "+%.1fs", $0) } ?? "—"
            context.draw(Text(label).font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(faded ? 0.3 : 0.85)),
                at: CGPoint(x: size.width - 12, y: rowY), anchor: .trailing)
        }
    }
}

private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next(upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

private struct TimelineLapRow: Identifiable {
    let timing: LiveDriverTiming
    let position: Int?
    let gap: String
    let lastLap: String
    let bestLap: String
    let tyre: String
    let tyreAge: String
    let laps: String
    let stops: String
    let recorded: Bool
    let retired: Bool
    var id: String { timing.id }
    var sortPosition: Int { position ?? .max }
    var sortName: String { timing.name }
    var sortLastLap: Int { Self.timeMilliseconds(lastLap) ?? .max }
    var sortBestLap: Int { Self.timeMilliseconds(bestLap) ?? .max }
    var bestLapMilliseconds: Int? { Self.timeMilliseconds(bestLap) }
    var sortLaps: Int { Int(laps) ?? .max }
    var sortStops: Int { Int(stops) ?? .max }
    var sortTyre: String { tyre }
    var gapSeconds: Double? {
        guard !retired else { return nil }
        if gap == "Leader" { return 0 }
        let cleaned = gap.trimmingCharacters(in: CharacterSet(charactersIn: "+s "))
        return Double(cleaned)
    }
    var sortGap: Double {
        if gap == "Leader" { return 0 }
        if retired && position == nil { return .infinity }
        if let lap = gap.split(separator: " ").last, lap.hasSuffix("L"),
           let count = Double(lap.dropLast()) { return count * 1_000 }
        return Double(gap.trimmingCharacters(in: CharacterSet(charactersIn: "+s"))) ?? .infinity
    }

    init(driver: TimelineRace.Driver, lap: Int, observed: LiveTimingSnapshot?, seed: UInt64) {
        timing = driver.timing
        position = driver.positions[lap - 1]
        retired = driver.retirementLap.map { lap >= $0 } ?? false
        if let actual = observed?.drivers.first(where: { $0.id == driver.id }) {
            recorded = true
            gap = retired ? "DNF · \(actual.gap ?? "—")" : actual.gap ?? "—"
            lastLap = retired ? "—" : actual.lastLap ?? "—"
            bestLap = actual.bestLap ?? "—"
            tyre = actual.currentTyre?.compound ?? "—"
            tyreAge = actual.currentTyre?.tyreAge.map { "\($0) laps" } ?? "Age unknown"
            laps = actual.laps.map(String.init) ?? String(min(lap, driver.retirementLap ?? lap))
            stops = actual.stops.map(String.init) ?? "—"
        } else {
            recorded = false
            let completed = min(lap, driver.retirementLap ?? lap)
            lastLap = retired ? "—" : Self.mockTime(driverID: driver.id, lap: lap, seed: seed).display
            bestLap = (1...completed).map { Self.mockTime(driverID: driver.id, lap: $0, seed: seed) }
                .min { $0.milliseconds < $1.milliseconds }?.display ?? "—"
            let mockGap = TimelineRace.mockGapSeconds(lap: lap, position: position ?? 22,
                                                      finalGap: driver.timing.gap,
                                                      finalPosition: driver.timing.position)
            gap = retired ? "DNF" : position == 1 ? "Leader" : String(format: "+%.1fs", mockGap)
            tyre = completed < 18 ? "SOFT" : completed < 39 ? "MEDIUM" : "HARD"
            tyreAge = "\(completed < 18 ? completed : completed < 39 ? completed - 17 : completed - 38) laps"
            laps = String(completed)
            stops = completed < 18 ? "0" : completed < 39 ? "1" : "2"
        }
    }

    private static func mockTime(driverID: String, lap: Int, seed: UInt64) -> (milliseconds: Int, display: String) {
        var random = SeededRandom(seed: seed ^ UInt64(lap * 1000 + (Int(driverID) ?? 0)))
        let seconds = 34 + random.next(upperBound: 10)
        let fraction = random.next(upperBound: 1000)
        return (seconds * 1000 + fraction, String(format: "1:%02d.%03d", seconds, fraction))
    }

    private static func timeMilliseconds(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Double(parts[1]),
              seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60_000 + Int((seconds * 1_000).rounded())
    }
}

struct RaceTimelineView: View {
    private enum ChartTab: String, CaseIterable { case positions = "Positions", gaps = "Gaps" }
    let store: LiveTimingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seed: UInt64 = 2026
    @State private var highlightedDriver: String?
    @State private var chartTab: ChartTab = .positions
    @State private var gapWindow = 10
    @State private var sortOrder: [KeyPathComparator<TimelineLapRow>] = [KeyPathComparator(\.sortPosition)]
    @State private var selectedLap = 1
    @State private var animatedLap = 1
    @State private var replayTask: Task<Void, Never>?
    @State private var manuallySelected = false
    @State private var replayStartedAt = Date()
    @State private var replayBaseLap = 1.0
    @State private var replayEndLap = 1
    @State private var isReplaying = false
    private let secondsPerLap = 0.28

    private var playbackTarget: Int {
        let snapshot = store.state.snapshot
        guard snapshot.sessionName == "Race", !snapshot.drivers.isEmpty else { return 0 }
        return min(56, max(snapshot.currentLap ?? 0, store.lapSnapshots.keys.max() ?? 0))
    }

    var body: some View {
        let snapshot = store.state.snapshot
        let race = TimelineRace(snapshot: snapshot, observedLaps: store.lapSnapshots, seed: seed)
        let observed = selectedLap == snapshot.currentLap ? snapshot : store.lapSnapshots[selectedLap]
        let rows = race.drivers.map { TimelineLapRow(driver: $0, lap: selectedLap, observed: observed, seed: seed) }
            .sorted { ($0.position ?? $0.timing.position ?? .max, Int($0.id) ?? .max) <
                      ($1.position ?? $1.timing.position ?? .max, Int($1.id) ?? .max) }
        GeometryReader { viewport in
         ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(title: "Race timeline", subtitle: subtitle(snapshot: snapshot))
                Spacer(minLength: 12)
                if !race.drivers.isEmpty {
                    Menu {
                        Button("All drivers") { highlightedDriver = nil }
                        ForEach(race.drivers) { driver in
                            Button("\(driver.timing.abbreviation) · \(driver.timing.name)") { highlightedDriver = driver.id }
                        }
                    } label: {
                        Label(selected(in: race)?.timing.abbreviation ?? "All drivers", systemImage: "line.3.horizontal.decrease")
                    }
                    Button { seed &+= 1 } label: {
                        Label("Regenerate mock laps", systemImage: "shuffle")
                    }
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 26)
            .padding(.top, 24)

            if race.drivers.isEmpty || playbackTarget == 0 {
                ContentUnavailableView("Waiting for F1 race timing", systemImage: "chart.xyaxis.line",
                                       description: Text(store.state.message ?? "Using the same feed as Live timing. The replay starts when its race roster and lap number arrive."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 12) {
                    Text("Lap \(selectedLap) of 56 · \(race.activeCount(at: selectedLap)) running")
                        .font(.headline).monospacedDigit()
                    Slider(value: Binding(get: { Double(selectedLap) }, set: { selectLap(Int($0)) }),
                           in: 1...56, step: 1).frame(width: 180).accessibilityLabel("Selected lap")
                    Stepper("", value: Binding(get: { selectedLap }, set: { selectLap($0) }), in: 1...56).labelsHidden()
                    Text(chartTab == .positions ? "Click any lap on the chart" : "Gaps to the race leader")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 26)

                HStack {
                    Picker("Chart", selection: $chartTab) {
                        ForEach(ChartTab.allCases, id: \.self) { tab in Text(tab.rawValue).tag(tab) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                    Spacer()
                    if chartTab == .gaps {
                        Picker("Recent laps", selection: $gapWindow) {
                            Text("Last 5 laps").tag(5)
                            Text("Last 10 laps").tag(10)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                    }
                }
                .padding(.horizontal, 26)

                if chartTab == .positions {
                 GeometryReader { chart in
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isReplaying)) { frame in
                        let progress = displayProgress(at: frame.date)
                        Canvas { context, size in
                            drawChart(context: context, size: size, race: race, progress: progress)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { point in
                            handleChartTap(point, size: chart.size, race: race, progress: progress)
                        }
                    }
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Race position chart for \(race.drivers.count) drivers. Selected lap \(selectedLap). Recorded laps use F1 timing; unrecorded laps are mock data.")
                }
                .frame(height: min(520, max(390, viewport.size.height * 0.65)))
                .padding(.horizontal, 26)
                } else {
                    GapTrendChart(race: race, snapshots: store.lapSnapshots,
                                  currentSnapshot: snapshot, selectedLap: selectedLap,
                                  window: gapWindow, seed: seed,
                                  highlightedDriver: $highlightedDriver,
                                  selectLap: selectLap)
                        .frame(height: min(520, max(390, viewport.size.height * 0.65)))
                        .padding(.horizontal, 26)
                }

                HStack(spacing: 12) {
                    Label("Mock VSC", systemImage: "square.fill").foregroundStyle(.orange)
                    Label("Mock SC", systemImage: "square.fill").foregroundStyle(.yellow)
                    Label("Mock red flag · lap 42", systemImage: "flag.fill").foregroundStyle(.red)
                    Text("Recorded laps use F1 timing · unrecorded laps are simulated")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 26)

                lapDetails(rows: rows, observed: observed)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 20)
            }
          }
         }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { startReplay(to: playbackTarget, fromStart: true) }
        .onChange(of: playbackTarget) { old, new in
            if old == 0 && new > 0 { startReplay(to: new, fromStart: true) }
            else if new > old && !manuallySelected { startReplay(to: new, fromStart: false) }
        }
        .onDisappear { replayTask?.cancel(); replayTask = nil }
    }

    private func selectLap(_ lap: Int) {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        manuallySelected = true
        selectedLap = lap
        animatedLap = lap
        replayBaseLap = Double(lap)
    }

    private func startReplay(to target: Int, fromStart: Bool) {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        guard target > 0 else { return }
        if fromStart {
            manuallySelected = false
            animatedLap = 1
            selectedLap = 1
        }
        if reduceMotion {
            animatedLap = target
            selectedLap = target
            replayBaseLap = Double(target)
            return
        }
        guard animatedLap < target else { return }
        replayBaseLap = Double(animatedLap)
        replayEndLap = target
        replayStartedAt = Date()
        isReplaying = true
        replayTask = Task { @MainActor in
            for lap in (animatedLap + 1)...target {
                do { try await Task.sleep(for: .seconds(secondsPerLap)) } catch { return }
                guard !Task.isCancelled else { return }
                animatedLap = lap
                selectedLap = lap
            }
            isReplaying = false
            replayBaseLap = Double(target)
            replayTask = nil
        }
    }

    private func displayProgress(at date: Date) -> Double {
        guard isReplaying else { return Double(animatedLap) }
        return min(Double(replayEndLap), replayBaseLap + date.timeIntervalSince(replayStartedAt) / secondsPerLap)
    }

    private func selected(in race: TimelineRace) -> TimelineRace.Driver? {
        race.drivers.first { $0.id == highlightedDriver }
    }

    private func subtitle(snapshot: LiveTimingSnapshot) -> String {
        let name = [snapshot.meetingName, snapshot.sessionName].compactMap { $0 }.joined(separator: " · ")
        return name.isEmpty ? "Connecting to F1 timing…" : "\(name) · 56 lap chart · \(snapshot.drivers.count) drivers"
    }

    private func lapDetails(rows: [TimelineLapRow], observed: LiveTimingSnapshot?) -> some View {
        let fastestID = rows.filter { $0.bestLapMilliseconds != nil }
            .min { ($0.bestLapMilliseconds ?? .max, $0.sortPosition, $0.id) <
                   ($1.bestLapMilliseconds ?? .max, $1.sortPosition, $1.id) }?.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lap \(selectedLap) timing").font(.title3.weight(.semibold))
                Text(rows.contains(where: { $0.recorded }) ? "Recorded from F1 timing" : "Simulated lap")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(rows.contains(where: { $0.recorded }) ? Color.green : Color.orange)
                Spacer()
                if let status = observed?.trackStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Table(rows.sorted(using: sortOrder), selection: $highlightedDriver, sortOrder: $sortOrder) {
                TableColumn("Pos", value: \.sortPosition) { row in
                    Text(row.position.map(String.init) ?? (row.retired ? "DNF" : "—")).monospacedDigit()
                }.width(36)
                TableColumn("Driver", value: \.sortName) { row in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Presentation.color(hex: row.timing.teamColor))
                            .frame(width: 3, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.timing.name).fontWeight(.medium).lineLimit(1)
                            Text(row.retired ? "DNF · \(row.laps) laps" : row.timing.team)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.width(min: 150, ideal: 210)
                TableColumn("Gap", value: \.sortGap) { row in Text(row.gap).monospacedDigit() }.width(76)
                TableColumn("Last lap", value: \.sortLastLap) { row in Text(row.lastLap).monospacedDigit() }.width(85)
                TableColumn("Best lap", value: \.sortBestLap) { row in
                    HStack(spacing: 5) {
                        if row.id == fastestID {
                            Circle().fill(.purple).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                                .accessibilityLabel("Fastest lap at this lap")
                        } else {
                            Color.clear.frame(width: 8, height: 8)
                        }
                        Text(row.bestLap).monospacedDigit()
                    }
                }.width(95)
                TableColumn("Tyre / age", value: \.sortTyre) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        TyreLabel(compound: row.tyre)
                        Text(row.tyreAge).font(.caption).foregroundStyle(.secondary)
                    }
                }.width(100)
                TableColumn("Laps", value: \.sortLaps) { row in Text(row.laps).monospacedDigit() }.width(38)
                TableColumn("Stops", value: \.sortStops) { row in Text(row.stops).monospacedDigit() }.width(38)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .frame(height: 330)
            if let row = rows.first(where: { $0.id == highlightedDriver }) {
                HStack(spacing: 14) {
                    Text(row.timing.name).fontWeight(.semibold)
                    Text("P\(row.position.map(String.init) ?? "—")")
                    Text("Gap \(row.gap)")
                    Text("Last \(row.lastLap)")
                    Text("Best \(row.bestLap)")
                    Text("\(row.tyre) · \(row.tyreAge)")
                    if row.recorded,
                       let actual = observed?.drivers.first(where: { $0.id == row.id }) {
                        Text(actual.sectors.enumerated().map { "S\($0.offset + 1) \($0.element)" }.joined(separator: "  "))
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
        }
    }

    private func interpolatedPosition(for driver: TimelineRace.Driver, at progress: Double) -> Double? {
        let lower = min(56, max(1, Int(progress.rounded(.down))))
        guard let first = driver.positions[lower - 1] else { return nil }
        guard lower < 56 else { return Double(first) }
        guard let next = driver.positions[lower] else {
            return progress == Double(lower) ? Double(first) : nil
        }
        return Double(first) + (Double(next) - Double(first)) * (progress - Double(lower))
    }

    private func handleChartTap(_ point: CGPoint, size: CGSize, race: TimelineRace, progress: Double) {
        let left: CGFloat = 48
        let right = size.width - 165
        let frontX = left + CGFloat((progress - 1) / 55) * (right - left)
        let top: CGFloat = 24
        let bottom = size.height - 70
        let count = max(race.drivers.count, 1)
        for driver in race.drivers {
            guard let retirement = driver.retirementLap, progress > Double(retirement),
                  let position = driver.positions[retirement - 1] else { continue }
            let nodeX = left + CGFloat(Double(retirement - 1) / 55) * (right - left)
            let nodeY = top + CGFloat(Double(position - 1) / Double(max(count - 1, 1))) * (bottom - top)
            if point.x >= nodeX - 7 && point.x <= nodeX + 162 && abs(point.y - nodeY) <= 10 {
                highlightedDriver = highlightedDriver == driver.id ? nil : driver.id
                return
            }
        }
        if point.x >= frontX - 7 && point.x <= frontX + 162 {
            for driver in race.drivers {
                guard let position = interpolatedPosition(for: driver, at: progress) else { continue }
                let nodeY = top + CGFloat((position - 1) / Double(max(count - 1, 1))) * (bottom - top)
                if abs(point.y - nodeY) <= 10 {
                    highlightedDriver = highlightedDriver == driver.id ? nil : driver.id
                    return
                }
            }
        }
        let fraction = (point.x - left) / (right - left)
        selectLap(min(56, max(1, Int((fraction * 55).rounded()) + 1)))
    }

    private func drawDriverNode(context: GraphicsContext, driver: TimelineRace.Driver,
                                at point: CGPoint, faded: Bool, retired: Bool) {
        let nodeColor = driver.color.opacity(faded ? 0.28 : 1)
        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                     with: .color(retired ? .red.opacity(faded ? 0.28 : 1) : nodeColor))
        let labelWidth = min(155, max(58, CGFloat(driver.timing.name.count) * 6.1 + 14))
        let label = Path(roundedRect: CGRect(x: point.x + 7, y: point.y - 9,
                                             width: labelWidth, height: 18), cornerRadius: 4)
        context.fill(label, with: .color(.black.opacity(0.88)))
        context.stroke(label, with: .color(retired ? .red.opacity(faded ? 0.28 : 0.9) : nodeColor.opacity(0.65)), lineWidth: 1)
        context.draw(Text(driver.timing.name).font(.system(size: 10, weight: .medium))
            .foregroundStyle(nodeColor), at: CGPoint(x: point.x + 13, y: point.y), anchor: .leading)
    }

    private func drawChart(context: GraphicsContext, size: CGSize, race: TimelineRace, progress: Double) {
        let left: CGFloat = 48
        let right = size.width - 165
        let top: CGFloat = 24
        let bottom = size.height - 70
        let count = max(race.drivers.count, 1)
        let x: (Double) -> CGFloat = { left + CGFloat(($0 - 1) / Double(race.laps - 1)) * (right - left) }
        let y: (Double) -> CGFloat = { top + CGFloat(($0 - 1) / Double(max(count - 1, 1))) * (bottom - top) }

        for position in stride(from: 1, through: count, by: 2) {
            var grid = Path()
            grid.move(to: CGPoint(x: left, y: y(Double(position))))
            grid.addLine(to: CGPoint(x: right, y: y(Double(position))))
            context.stroke(grid, with: .color(.white.opacity(0.13)), lineWidth: 1)
            context.draw(Text(String(position)).font(.caption2).foregroundStyle(.white.opacity(0.65)),
                         at: CGPoint(x: left - 13, y: y(Double(position))), anchor: .trailing)
        }
        let lapTicks = Array(Set([1, 2, 42, 56] + Array(stride(from: 5, through: 55, by: 5)))).sorted()
        for lap in lapTicks {
            var grid = Path()
            grid.move(to: CGPoint(x: x(Double(lap)), y: top))
            grid.addLine(to: CGPoint(x: x(Double(lap)), y: bottom))
            context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
            context.draw(Text(String(lap)).font(.caption2).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: x(Double(lap)) + (lap == 56 ? 8 : 0), y: bottom + 16),
                         anchor: lap == 56 ? .leading : .center)
        }
        for interval in race.mockCautionLaps {
            let start = x(Double(interval.lowerBound)) - 4
            let width = x(Double(interval.upperBound)) - start + 4
            context.fill(Path(CGRect(x: start, y: top, width: width, height: bottom - top)),
                         with: .color(.orange.opacity(0.2)))
        }
        for interval in race.mockSafetyCarLaps {
            let start = x(Double(interval.lowerBound)) - 4
            let width = x(Double(interval.upperBound)) - start + 4
            let band = Path(CGRect(x: start, y: top, width: width, height: bottom - top))
            context.fill(band, with: .color(.yellow.opacity(0.46)))
            context.stroke(band, with: .color(.yellow.opacity(0.85)), lineWidth: 1)
        }

        let selectionX = x(progress)
        context.fill(Path(CGRect(x: selectionX - 1, y: top, width: 2, height: bottom - top)),
                     with: .color(.white.opacity(0.75)))

        for driver in race.drivers {
            var line = Path()
            var hasPoint = false
            let wholeLaps = min(56, max(1, Int(progress.rounded(.down))))
            for (index, position) in driver.positions.prefix(wholeLaps).enumerated() {
                guard let position, (1...count).contains(position) else { hasPoint = false; continue }
                let point = CGPoint(x: x(Double(index + 1)), y: y(Double(position)))
                if hasPoint { line.addLine(to: point) } else { line.move(to: point) }
                hasPoint = true
            }
            if progress > Double(wholeLaps), let position = interpolatedPosition(for: driver, at: progress) {
                line.addLine(to: CGPoint(x: x(progress), y: y(position)))
            }
            let faded = highlightedDriver != nil && highlightedDriver != driver.id
            context.stroke(line, with: .color(driver.color.opacity(faded ? 0.14 : 0.95)),
                           style: StrokeStyle(lineWidth: faded ? 1 : highlightedDriver == nil ? 1.7 : 2.6, lineJoin: .round))
            if let position = interpolatedPosition(for: driver, at: progress), position >= 1, position <= Double(count) {
                drawDriverNode(context: context, driver: driver,
                               at: CGPoint(x: x(progress), y: y(position)), faded: faded, retired: false)
            } else if let retirement = driver.retirementLap, progress > Double(retirement),
                      let position = driver.positions[retirement - 1] {
                drawDriverNode(context: context, driver: driver,
                               at: CGPoint(x: x(Double(retirement)), y: y(Double(position))),
                               faded: faded, retired: true)
            }
        }
        for lap in race.mockRedFlagLaps {
            var marker = Path()
            marker.move(to: CGPoint(x: x(Double(lap)), y: top))
            marker.addLine(to: CGPoint(x: x(Double(lap)), y: bottom))
            context.stroke(marker, with: .color(.red), lineWidth: 2.5)
            ChartEventMarker.redFlag(context: context, x: x(Double(lap)), y: bottom + 36)
        }
        for interval in race.mockSafetyCarLaps {
            ChartEventMarker.pill(context: context, x: x(Double(interval.lowerBound)),
                                  y: bottom + 36, title: "SC", color: .yellow)
        }
        for interval in race.mockCautionLaps {
            ChartEventMarker.pill(context: context, x: x(Double(interval.lowerBound)),
                                  y: bottom + 36, title: "VSC", color: .orange)
        }
        context.draw(Text("Lap").font(.caption).foregroundStyle(.white.opacity(0.75)),
                     at: CGPoint(x: (left + right) / 2, y: size.height - 12))
    }
}
