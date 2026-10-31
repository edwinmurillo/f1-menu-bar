import F1Core
import SwiftUI

struct RaceHistoryChart: View {
    enum Kind: Hashable { case positions, gaps }
    let history: RaceHistory
    let selectedLap: Int
    let highlightedDriver: String?
    let kind: Kind
    let gapWindow: Int
    let selectLap: (Int) -> Void
    private var isPracticeTimeline: Bool {
        history.sourceID.hasPrefix("live:") &&
            (history.request.session?.name.localizedCaseInsensitiveContains("Practice") == true ||
             history.request.session?.name.localizedCaseInsensitiveContains("Qualifying") == true ||
             history.request.session?.name.localizedCaseInsensitiveContains("Shootout") == true)
    }

    private var drivers: [RaceHistoryDriver] {
        let latest = history.laps.last?.timings ?? []
        let sorted = history.drivers.sorted { rank($0, in: latest) < rank($1, in: latest) }
        return kind == .gaps ? Array(sorted.prefix(10)) : sorted
    }
    private func rank(_ driver: RaceHistoryDriver, in timings: [RaceHistoryTiming]) -> (Int, String) {
        (timings.first { $0.driverID == driver.id }?.position ?? .max, driver.name)
    }
    private var shownLaps: [RaceHistoryLap] {
        let prior = history.laps.filter { $0.number <= selectedLap }
        return kind == .gaps ? Array(prior.suffix(gapWindow)) : prior
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in draw(context: context, size: size) }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    let first = kind == .gaps ? shownLaps.first?.number ?? 1 : 1
                    let last = kind == .gaps ? selectedLap : history.lastLap
                    let fraction = min(1, max(0, (point.x - 45) / max(geometry.size.width - 165, 1)))
                    let value = Double(first) + Double(max(last - first, 0)) * Double(fraction)
                    if let lap = history.laps.min(by: { abs(Double($0.number) - value) < abs(Double($1.number) - value) }) { selectLap(lap.number) }
                }
        }
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .positions ? "Driver positions through \(isPracticeTimeline ? "best-lap update" : "lap") \(selectedLap) of \(history.lastLap)" : "Recorded gaps to the leader through \(isPracticeTimeline ? "update" : "lap") \(selectedLap)")
        .accessibilityHint("Use the lap progress slider, previous and next buttons, or the timing rows for accessible details.")
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let first = kind == .gaps ? shownLaps.first?.number ?? 1 : 1
        let last = kind == .gaps ? selectedLap : history.lastLap
        let left: CGFloat = 45, right = max(46, size.width - 120), top: CGFloat = 28, bottom = size.height - 50
        let x: (Int) -> CGFloat = { left + CGFloat($0 - first) / CGFloat(max(last - first, 1)) * (right - left) }
        let maxGap = max(5, shownLaps.flatMap(\.timings).compactMap { $0.gap?.seconds }.max() ?? 5)
        let y: (Double) -> CGFloat = { value in
            kind == .positions
                ? top + CGFloat(value - 1) / CGFloat(max(history.positionsCount - 1, 1)) * (bottom - top)
                : top + CGFloat(value / maxGap) * (bottom - top)
        }
        if kind == .positions {
            for position in stride(from: 1, through: max(history.positionsCount, 1), by: 2) {
                grid(context: context, label: String(position), y: y(Double(position)), left: left, right: right)
            }
        } else {
            for tick in 0...4 {
                let value = maxGap * Double(tick) / 4
                grid(context: context, label: String(format: "%.0fs", value), y: y(value), left: left, right: right)
            }
            context.draw(Text("GAP TO LEADER · SECONDS").font(.caption2).foregroundStyle(.white.opacity(0.6)),
                         at: CGPoint(x: left, y: 12), anchor: .leading)
        }
        for lap in history.laps where lap.number >= first && lap.number <= last &&
            (lap.number == first || lap.number == last || lap.number.isMultiple(of: kind == .gaps ? 1 : 10)) {
            let label = isPracticeTimeline ? lap.recordedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? String(lap.number) : String(lap.number)
            context.draw(Text(label).font(.caption2).foregroundStyle(.white.opacity(0.65)),
                         at: CGPoint(x: x(lap.number), y: bottom + 16))
        }
        // Actual race-control markers only. No inferred caution intervals.
        let markers = history.events.filter { event in
            event.lap.map { $0 >= first && $0 <= selectedLap } == true &&
                (event.flag == "RED" || event.category == "SafetyCar")
        }
        for lap in Set(markers.compactMap(\.lap)) {
            let red = markers.contains { $0.lap == lap && $0.flag == "RED" }
            var marker = Path(); marker.move(to: CGPoint(x: x(lap), y: top)); marker.addLine(to: CGPoint(x: x(lap), y: bottom))
            context.stroke(marker, with: .color((red ? Color.red : Color.yellow).opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        var cursor = Path(); cursor.move(to: CGPoint(x: x(selectedLap), y: top)); cursor.addLine(to: CGPoint(x: x(selectedLap), y: bottom))
        context.stroke(cursor, with: .color(.white.opacity(0.45)), lineWidth: 1)
        for driver in drivers {
            var line = Path(); var previous: Int?; var endpoint: CGPoint?
            let faded = highlightedDriver != nil && highlightedDriver != driver.id
            // The plot is always black; semantic secondary can be black in light mode.
            let color = driver.teamColor.flatMap { $0.count == 6 && UInt32($0, radix: 16) != nil ? Presentation.color(hex: $0) : nil } ?? .white
            for lap in shownLaps {
                let timing = lap.timings.first { $0.driverID == driver.id }
                let value = kind == .positions ? timing?.position.map(Double.init) : timing?.gap?.seconds
                guard let value else { previous = nil; continue }
                let point = CGPoint(x: x(lap.number), y: y(value))
                if previous == lap.number - 1 { line.addLine(to: point) } else { line.move(to: point) }
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                             with: .color(color.opacity(faded ? 0.14 : 0.85)))
                previous = lap.number; endpoint = point
            }
            context.stroke(line, with: .color(color.opacity(faded ? 0.14 : 0.95)), lineWidth: highlightedDriver == driver.id ? 3 : 1.8)
            if let endpoint {
                context.fill(Path(ellipseIn: CGRect(x: endpoint.x - 2.5, y: endpoint.y - 2.5, width: 5, height: 5)), with: .color(color.opacity(faded ? 0.2 : 1)))
                context.draw(Text(driver.abbreviation).font(.system(size: 10, weight: .medium)).foregroundStyle(color.opacity(faded ? 0.2 : 1)),
                             at: CGPoint(x: endpoint.x + 8, y: endpoint.y), anchor: .leading)
            }
        }
        context.draw(Text(isPracticeTimeline ? "Best-lap updates" : "Session lap").font(.caption2).foregroundStyle(.white.opacity(0.6)),
                     at: CGPoint(x: (left + right) / 2, y: size.height - 9))
    }
    private func grid(context: GraphicsContext, label: String, y: CGFloat, left: CGFloat, right: CGFloat) {
        var path = Path(); path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: right, y: y))
        context.stroke(path, with: .color(.white.opacity(0.1)), lineWidth: 1)
        context.draw(Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6)), at: CGPoint(x: left - 10, y: y), anchor: .trailing)
    }
}
