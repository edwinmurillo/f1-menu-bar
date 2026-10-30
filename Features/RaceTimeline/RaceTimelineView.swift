import F1Core
import SwiftUI

/// The timeline contains only snapshots received during this app session.
struct RecordedRaceTimeline {
    let snapshots: [Int: LiveTimingSnapshot]

    init(current: LiveTimingSnapshot, saved: [Int: LiveTimingSnapshot]) {
        let sessionID = current.sessionName == "Race" ? current.sessionID : saved.values.first?.sessionID
        guard let sessionID else { snapshots = [:]; return }
        var matching = saved.filter {
            $0.key > 0 && $0.value.sessionID == sessionID && $0.value.sessionName == "Race"
        }
        if current.sessionName == "Race", current.sessionID == sessionID,
           let lap = current.currentLap, lap > 0, !current.drivers.isEmpty {
            matching[lap] = current
        }
        snapshots = matching
    }

    var laps: [Int] { snapshots.keys.sorted() }
    var latest: LiveTimingSnapshot? { laps.last.flatMap { snapshots[$0] } }
    var drivers: [LiveDriverTiming] {
        (latest?.drivers ?? []).sorted {
            ($0.position ?? .max, $0.name) < ($1.position ?? .max, $1.name)
        }
    }
    var topTenDrivers: [LiveDriverTiming] { Array(drivers.prefix(10)) }

    func driver(_ id: String, at lap: Int) -> LiveDriverTiming? {
        snapshots[lap]?.drivers.first { $0.id == id }
    }

    static func gapSeconds(_ driver: LiveDriverTiming) -> Double? {
        if driver.position == 1 { return 0 }
        guard let gap = driver.gap else { return nil }
        return Double(gap.trimmingCharacters(in: CharacterSet(charactersIn: "+s ")))
    }
}

private struct RecordedLapRow: Identifiable {
    let driver: LiveDriverTiming
    var id: String { driver.id }
    var sortPosition: Int { driver.position ?? .max }
    var sortName: String { driver.name }
    var sortGap: Double { RecordedRaceTimeline.gapSeconds(driver) ?? .infinity }
    var sortLastLap: Int { Self.milliseconds(driver.lastLap) ?? .max }
    var sortBestLap: Int { Self.milliseconds(driver.bestLap) ?? .max }
    var sortLaps: Int { driver.laps ?? .max }
    var sortStops: Int { driver.stops ?? .max }
    var sortTyre: String { driver.currentTyre?.compound ?? "" }

    static func milliseconds(_ time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Double(parts[1]),
              seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60_000 + Int((seconds * 1_000).rounded())
    }
}

struct RaceTimelineView: View {
    private enum ChartTab: String, CaseIterable { case positions = "Positions", gaps = "Gaps" }
    let store: LiveTimingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chartTab: ChartTab = .positions
    @State private var gapWindow = 10
    @State private var highlightedDriver: String?
    @State private var selectedIndex = 0
    @State private var revealedCount = 1
    @State private var replayTask: Task<Void, Never>?
    @State private var sortOrder: [KeyPathComparator<RecordedLapRow>] = [KeyPathComparator(\.sortPosition)]

    var body: some View {
        let history = RecordedRaceTimeline(current: store.state.snapshot, saved: store.lapSnapshots)
        let index = min(selectedIndex, max(history.laps.count - 1, 0))
        let selectedLap = history.laps.isEmpty ? nil : history.laps[index]
        let snapshot = selectedLap.flatMap { history.snapshots[$0] }
        GeometryReader { viewport in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "Race timeline", subtitle: "Recorded laps from the current app session")
                        Spacer()
                        if !history.drivers.isEmpty {
                            Menu {
                                Button("All drivers") { highlightedDriver = nil }
                                ForEach(history.drivers) { driver in
                                    Button("\(driver.abbreviation) · \(driver.name)") { highlightedDriver = driver.id }
                                }
                            } label: {
                                Label(history.drivers.first { $0.id == highlightedDriver }?.abbreviation ?? "All drivers",
                                      systemImage: "line.3.horizontal.decrease")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 26)
                    .padding(.top, 24)

                    if let selectedLap, let snapshot {
                        HStack(spacing: 12) {
                            Text("Lap \(selectedLap) · \(history.laps.count) recorded")
                                .font(.headline).monospacedDigit()
                            Slider(value: Binding(get: { Double(index) },
                                                  set: { selectIndex(Int($0), count: history.laps.count) }),
                                   in: 0...Double(max(history.laps.count - 1, 1)), step: 1)
                                .frame(width: 180)
                                .disabled(history.laps.count < 2)
                                .accessibilityLabel("Recorded lap")
                            Stepper("", value: Binding(get: { index },
                                                       set: { selectIndex($0, count: history.laps.count) }),
                                    in: 0...max(history.laps.count - 1, 0))
                                .labelsHidden().disabled(history.laps.count < 2)
                            Text("Only laps captured while connected are shown")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 26)

                        HStack {
                            Picker("Chart", selection: $chartTab) {
                                ForEach(ChartTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented).frame(width: 230)
                            Spacer()
                            if chartTab == .gaps {
                                Picker("Recorded laps", selection: $gapWindow) {
                                    Text("Last 5 laps").tag(5)
                                    Text("Last 10 laps").tag(10)
                                }
                                .pickerStyle(.segmented).frame(width: 230)
                            }
                        }
                        .padding(.horizontal, 26)

                        GeometryReader { chart in
                            Canvas { context, size in
                                if chartTab == .positions {
                                    drawPositions(context: context, size: size, history: history,
                                                  visibleLaps: Array(history.laps.prefix(revealedCount)))
                                } else {
                                    drawGaps(context: context, size: size, history: history,
                                             laps: Array(history.laps.prefix(index + 1).suffix(gapWindow)))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { point in
                                let legendLeft = chart.size.width - 118
                                if chartTab == .gaps, point.x >= legendLeft {
                                    let drivers = history.topTenDrivers
                                    let row = Int((point.y - 35) / ((chart.size.height - 65) / CGFloat(max(drivers.count, 1))))
                                    if drivers.indices.contains(row) {
                                        let id = drivers[row].id
                                        highlightedDriver = highlightedDriver == id ? nil : id
                                    }
                                } else {
                                    let fraction = min(1, max(0, (point.x - 54) / max(1, chart.size.width - 190)))
                                    let range = chartTab == .gaps ? Array(history.laps.prefix(index + 1).suffix(gapWindow)) : history.laps
                                    if !range.isEmpty {
                                        let lap = range.first! + Int((Double(range.last! - range.first!) * Double(fraction)).rounded())
                                        if let nearest = history.laps.enumerated().min(by: { abs($0.element - lap) < abs($1.element - lap) }) {
                                            selectIndex(nearest.offset, count: history.laps.count)
                                        }
                                    }
                                }
                            }
                        }
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(height: min(520, max(390, viewport.size.height * 0.65)))
                        .padding(.horizontal, 26)

                        lapTable(snapshot: snapshot, lap: selectedLap)
                            .padding(.horizontal, 26)
                            .padding(.bottom, 20)
                    } else {
                        ContentUnavailableView("No race laps recorded yet", systemImage: "chart.xyaxis.line",
                                               description: Text("Open Live timing or leave this tab visible during a race. Laps are kept in memory until the app closes."))
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { replay(laps: history.laps) }
        .onChange(of: history.laps) { _, laps in replay(laps: laps) }
        .onDisappear { replayTask?.cancel(); replayTask = nil }
    }

    private func selectIndex(_ index: Int, count: Int) {
        replayTask?.cancel(); replayTask = nil
        selectedIndex = min(max(index, 0), max(count - 1, 0))
        revealedCount = selectedIndex + 1
    }

    private func replay(laps: [Int]) {
        replayTask?.cancel(); replayTask = nil
        guard !laps.isEmpty else { return }
        if reduceMotion {
            selectedIndex = laps.count - 1
            revealedCount = laps.count
            return
        }
        selectedIndex = 0
        revealedCount = 1
        guard laps.count > 1 else { return }
        replayTask = Task { @MainActor in
            for index in 1..<laps.count {
                do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
                guard !Task.isCancelled else { return }
                selectedIndex = index
                revealedCount = index + 1
            }
            replayTask = nil
        }
    }

    private func lapTable(snapshot: LiveTimingSnapshot, lap: Int) -> some View {
        let rows = snapshot.drivers.map(RecordedLapRow.init)
        let fastestID = rows.filter { $0.sortBestLap != .max }
            .min { ($0.sortBestLap, $0.sortPosition, $0.id) < ($1.sortBestLap, $1.sortPosition, $1.id) }?.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lap \(lap) timing").font(.title3.weight(.semibold))
                Spacer()
                if let status = snapshot.trackStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Table(rows.sorted(using: sortOrder), selection: $highlightedDriver, sortOrder: $sortOrder) {
                TableColumn("Pos", value: \.sortPosition) { row in Text(row.driver.position.map(String.init) ?? "—").monospacedDigit() }.width(36)
                TableColumn("Driver", value: \.sortName) { row in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2).fill(Presentation.color(hex: row.driver.teamColor)).frame(width: 3, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.driver.name).fontWeight(.medium).lineLimit(1)
                            Text(row.driver.team).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.width(min: 150, ideal: 210)
                TableColumn("Gap", value: \.sortGap) { row in Text(row.driver.gap ?? "—").monospacedDigit() }.width(76)
                TableColumn("Last lap", value: \.sortLastLap) { row in Text(row.driver.lastLap ?? "—").monospacedDigit() }.width(85)
                TableColumn("Best lap", value: \.sortBestLap) { row in
                    HStack(spacing: 5) {
                        if row.id == fastestID {
                            Circle().fill(.purple).frame(width: 8, height: 8)
                                .accessibilityLabel("Fastest lap at this lap")
                        } else { Color.clear.frame(width: 8, height: 8) }
                        Text(row.driver.bestLap ?? "—").monospacedDigit()
                    }
                }.width(95)
                TableColumn("Tyre / age", value: \.sortTyre) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        TyreLabel(compound: row.driver.currentTyre?.compound)
                        Text(row.driver.currentTyre?.tyreAge.map { "\($0) laps" } ?? "Age unknown")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.width(100)
                TableColumn("Laps", value: \.sortLaps) { row in Text(row.driver.laps.map(String.init) ?? "—").monospacedDigit() }.width(38)
                TableColumn("Stops", value: \.sortStops) { row in Text(row.driver.stops.map(String.init) ?? "—").monospacedDigit() }.width(38)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .frame(height: 330)
        }
    }

    private func drawPositions(context: GraphicsContext, size: CGSize,
                               history: RecordedRaceTimeline, visibleLaps: [Int]) {
        guard let first = history.laps.first, let last = history.laps.last else { return }
        let left: CGFloat = 48, right = size.width - 130, top: CGFloat = 26, bottom = size.height - 50
        let x: (Int) -> CGFloat = { left + CGFloat($0 - first) / CGFloat(max(last - first, 1)) * (right - left) }
        let y: (Int) -> CGFloat = { top + CGFloat($0 - 1) / CGFloat(max(history.drivers.count - 1, 1)) * (bottom - top) }
        for position in stride(from: 1, through: max(history.drivers.count, 1), by: 2) {
            var grid = Path(); grid.move(to: CGPoint(x: left, y: y(position)))
            grid.addLine(to: CGPoint(x: right, y: y(position)))
            context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)
            context.draw(Text(String(position)).font(.caption2).foregroundStyle(.white.opacity(0.65)),
                         at: CGPoint(x: left - 10, y: y(position)), anchor: .trailing)
        }
        for lap in history.laps where lap == first || lap == last || lap.isMultiple(of: 5) {
            context.draw(Text(String(lap)).font(.caption2).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: x(lap), y: bottom + 17))
        }
        for driver in history.drivers {
            var path = Path(); var previousLap: Int?
            var endpoint: CGPoint?
            for lap in visibleLaps {
                guard let position = history.driver(driver.id, at: lap)?.position else { previousLap = nil; continue }
                let point = CGPoint(x: x(lap), y: y(position))
                if previousLap == lap - 1 { path.addLine(to: point) } else { path.move(to: point) }
                previousLap = lap; endpoint = point
            }
            let color = Presentation.color(hex: driver.teamColor)
            let faded = highlightedDriver != nil && highlightedDriver != driver.id
            context.stroke(path, with: .color(color.opacity(faded ? 0.14 : 0.95)), lineWidth: faded ? 1 : 2)
            if let endpoint {
                context.draw(Text(driver.abbreviation).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color.opacity(faded ? 0.25 : 1)),
                    at: CGPoint(x: endpoint.x + 7, y: endpoint.y), anchor: .leading)
            }
        }
        context.draw(Text("Lap").font(.caption).foregroundStyle(.white.opacity(0.75)),
                     at: CGPoint(x: (left + right) / 2, y: size.height - 10))
    }

    private func drawGaps(context: GraphicsContext, size: CGSize,
                          history: RecordedRaceTimeline, laps: [Int]) {
        guard let first = laps.first, let last = laps.last else { return }
        let left: CGFloat = 54, right = size.width - 136, top: CGFloat = 35, bottom = size.height - 45
        let x: (Int) -> CGFloat = { left + CGFloat($0 - first) / CGFloat(max(last - first, 1)) * (right - left) }
        let gapValues = laps.flatMap { lap in history.topTenDrivers.compactMap { history.driver($0.id, at: lap).flatMap(RecordedRaceTimeline.gapSeconds) } }
        let maxGap = max(5, (gapValues.max() ?? 0).rounded(.up))
        let y: (Double) -> CGFloat = { top + CGFloat($0 / maxGap) * (bottom - top) }
        context.draw(Text("GAP TO LEADER · SECONDS BEHIND").font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75)), at: CGPoint(x: left, y: 16), anchor: .leading)
        for tick in 0...4 {
            let seconds = maxGap * Double(tick) / 4
            var grid = Path(); grid.move(to: CGPoint(x: left, y: y(seconds)))
            grid.addLine(to: CGPoint(x: right, y: y(seconds)))
            context.stroke(grid, with: .color(.white.opacity(0.13)), lineWidth: 1)
            context.draw(Text(tick == 0 ? "0" : String(format: "−%.0f", seconds)).font(.caption2)
                .foregroundStyle(.white.opacity(0.65)), at: CGPoint(x: left - 8, y: y(seconds)), anchor: .trailing)
        }
        for lap in laps {
            context.draw(Text(String(lap)).font(.caption2).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: x(lap), y: bottom + 16))
        }
        let activeHighlight = history.topTenDrivers.contains { $0.id == highlightedDriver } ? highlightedDriver : nil
        for driver in history.topTenDrivers {
            var path = Path(); var previousLap: Int?
            for lap in laps {
                guard let actual = history.driver(driver.id, at: lap),
                      let gap = RecordedRaceTimeline.gapSeconds(actual) else { previousLap = nil; continue }
                let point = CGPoint(x: x(lap), y: y(gap))
                if previousLap == lap - 1 { path.addLine(to: point) } else { path.move(to: point) }
                previousLap = lap
            }
            let faded = activeHighlight != nil && activeHighlight != driver.id
            context.stroke(path, with: .color(Presentation.color(hex: driver.teamColor).opacity(faded ? 0.15 : 0.9)),
                           lineWidth: faded ? 1 : activeHighlight == driver.id ? 3 : 1.7)
        }
        let legendLeft = size.width - 116
        context.draw(Text("LAP \(last)").font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75)), at: CGPoint(x: legendLeft, y: 16), anchor: .leading)
        for (index, driver) in history.topTenDrivers.enumerated() {
            let rowY = top + (CGFloat(index) + 0.5) * (size.height - 65) / CGFloat(max(history.topTenDrivers.count, 1))
            let faded = activeHighlight != nil && activeHighlight != driver.id
            let color = Presentation.color(hex: driver.teamColor)
            context.fill(Path(ellipseIn: CGRect(x: legendLeft, y: rowY - 3, width: 6, height: 6)),
                         with: .color(color.opacity(faded ? 0.25 : 1)))
            context.draw(Text(driver.abbreviation).font(.system(size: 10, weight: .medium))
                .foregroundStyle(color.opacity(faded ? 0.3 : 1)),
                at: CGPoint(x: legendLeft + 11, y: rowY), anchor: .leading)
            let gap = history.driver(driver.id, at: last).flatMap(RecordedRaceTimeline.gapSeconds)
            context.draw(Text(gap.map { String(format: "+%.1fs", $0) } ?? "—")
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(faded ? 0.3 : 0.85)),
                at: CGPoint(x: size.width - 12, y: rowY), anchor: .trailing)
        }
        context.draw(Text("Lap").font(.caption).foregroundStyle(.white.opacity(0.75)),
                     at: CGPoint(x: (left + right) / 2, y: size.height - 10))
    }
}
