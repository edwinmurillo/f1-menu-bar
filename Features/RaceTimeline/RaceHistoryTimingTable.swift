import F1Core
import SwiftUI

struct RaceHistoryTimingTable: View {
    private enum Sort: String { case position = "Pos", driver = "Driver", gap = "Gap", last = "Lap time", best = "Best so far", tyre = "Tyre / age", history = "Tyre history", stops = "Stops", pit = "Pit" }
    let history: RaceHistory
    let lap: Int
    @Binding var highlightedDriver: String?
    @State private var sort: Sort = .position
    @State private var ascending = true
    private var isPracticeTimeline: Bool {
        history.sourceID.hasPrefix("live:") &&
            (history.request.session?.name.localizedCaseInsensitiveContains("Practice") == true ||
             history.request.session?.name.localizedCaseInsensitiveContains("Qualifying") == true ||
             history.request.session?.name.localizedCaseInsensitiveContains("Shootout") == true)
    }

    private var rows: [(RaceHistoryDriver, RaceHistoryTiming?)] {
        let timings = history.laps.first { $0.number == lap }?.timings ?? []
        return history.drivers.map { driver in (driver, timings.first { $0.driverID == driver.id }) }.sorted { a, b in
            let order: Bool
            if a.0.id == b.0.id { return false }
            if a.1 == nil || b.1 == nil { return a.1 != nil && b.1 == nil }
            switch sort {
            case .driver: order = (a.0.name, a.0.id) < (b.0.name, b.0.id)
            case .position: order = (a.1?.position ?? .max, a.0.name, a.0.id) < (b.1?.position ?? .max, b.0.name, b.0.id)
            case .gap: order = (a.1?.gap?.seconds ?? .infinity, a.0.name, a.0.id) < (b.1?.gap?.seconds ?? .infinity, b.0.name, b.0.id)
            case .last: order = (a.1?.duration ?? .infinity, a.0.name, a.0.id) < (b.1?.duration ?? .infinity, b.0.name, b.0.id)
            case .best: order = (a.1?.bestDuration ?? .infinity, a.0.name, a.0.id) < (b.1?.bestDuration ?? .infinity, b.0.name, b.0.id)
            case .tyre: order = (a.1?.compound ?? "", a.0.name, a.0.id) < (b.1?.compound ?? "", b.0.name, b.0.id)
            case .history:
                let first = (a.1?.tyreHistory ?? []).map { $0.compound ?? "" }.joined(separator: "-")
                let second = (b.1?.tyreHistory ?? []).map { $0.compound ?? "" }.joined(separator: "-")
                order = (first, a.0.name, a.0.id) < (second, b.0.name, b.0.id)
            case .stops: order = (a.1?.stops ?? .max, a.0.name, a.0.id) < (b.1?.stops ?? .max, b.0.name, b.0.id)
            case .pit:
                let first = a.1?.inPit == true ? 0 : a.1?.pitOut == true ? 1 : 2
                let second = b.1?.inPit == true ? 0 : b.1?.pitOut == true ? 1 : 2
                order = (first, a.0.name, a.0.id) < (second, b.0.name, b.0.id)
            }
            return ascending ? order : !order
        }
    }
    private var fastest: Double? { rows.compactMap { $0.1?.bestDuration }.min() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isPracticeTimeline ? "Best times · update \(lap)" : "Lap \(lap) timing").font(.title3.weight(.semibold))
                Spacer()
                Text("\(rows.count) drivers").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    heading(.position, width: 32)
                    heading(.driver).frame(maxWidth: .infinity, alignment: .leading)
                    heading(.gap, width: 66)
                    heading(.last, width: 78)
                    heading(.best, width: 82)
                    heading(.tyre, width: 98)
                    heading(.history, width: 170)
                    heading(.stops, width: 42)
                    heading(.pit, width: 34)
                }.padding(.horizontal, 10).padding(.vertical, 10)
                    .background(.quaternary.opacity(0.35))
                ForEach(rows, id: \.0.id) { driver, timing in
                    Button { highlightedDriver = highlightedDriver == driver.id ? nil : driver.id } label: {
                        HStack(spacing: 10) {
                            Text(timing?.position.map(String.init) ?? "—").frame(width: 32, alignment: .leading)
                            HStack(spacing: 8) {
                                Capsule().fill(Presentation.color(hex: driver.teamColor)).frame(width: 3, height: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(driver.name).fontWeight(.medium).lineLimit(1)
                                    Text(timing?.bestDuration == nil && isPracticeTimeline ? "No best time yet" : timing == nil ? "No lap recorded" : driver.team)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(HistoryFormat.gap(timing?.gap)).frame(width: 66, alignment: .leading)
                            Text(HistoryFormat.duration(timing?.duration)).frame(width: 78, alignment: .leading)
                            Text(HistoryFormat.duration(timing?.bestDuration))
                                .foregroundStyle(timing?.bestDuration != nil && timing?.bestDuration == fastest ? Color.purple : Color.primary)
                                .frame(width: 82, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                TyreLabel(compound: timing?.compound)
                                Text(timing?.tyreAge.map { "\($0) laps" } ?? "Age unknown").font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 98, alignment: .leading)
                            TyreHistoryLabel(segments: timing?.tyreHistory)
                                .frame(width: 170, alignment: .leading)
                            Text(timing?.stops.map(String.init) ?? "—").frame(width: 42, alignment: .leading)
                            Text(timing?.inPit == true ? "PIT" : timing?.pitOut == true ? "OUT" : "—")
                                .foregroundStyle(timing?.inPit == true ? Color.orange : timing?.pitOut == true ? Color.green : Color.secondary)
                                .frame(width: 34, alignment: .leading)
                        }
                        .font(.callout).monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(highlightedDriver == driver.id ? Presentation.accent.opacity(0.12) : Color.clear)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityElement(children: .combine)
                        .accessibilityAddTraits(highlightedDriver == driver.id ? [.isSelected] : [])
                    Divider()
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("All driver rows are shown here. Scroll the page to read the full timing and race-control details.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func heading(_ value: Sort, width: CGFloat? = nil) -> some View {
        Button {
            if sort == value { ascending.toggle() } else { sort = value; ascending = true }
        } label: {
            HStack(spacing: 3) {
                Text(isPracticeTimeline && value == .last ? "Last time" : isPracticeTimeline && value == .best ? "Best time" : value.rawValue).lineLimit(1)
                if sort == value { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8)) }
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }.buttonStyle(.plain).frame(width: width, alignment: .leading).help("Sort by \(value.rawValue)")
    }
}

enum HistoryFormat {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds <= 86_400 else { return "—" }
        let milliseconds = Int((seconds * 1_000).rounded())
        return String(format: "%d:%02d.%03d", milliseconds / 60_000, (milliseconds / 1000) % 60, milliseconds % 1000)
    }
    static func gap(_ value: RaceHistoryGap?) -> String {
        switch value {
        case .seconds(let seconds): seconds == 0 ? "Leader" : String(format: "+%.3f", seconds)
        case .laps(let count): "+\(count) lap\(count == 1 ? "" : "s")"
        case nil: "—"
        }
    }
}
