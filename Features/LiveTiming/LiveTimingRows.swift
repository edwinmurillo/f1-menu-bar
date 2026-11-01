import F1Core
import SwiftUI

struct LiveTimingFilter: Equatable {
    var driverID: String?
    var team: String?

    func apply(to drivers: [LiveDriverTiming]) -> [LiveDriverTiming] {
        drivers.filter { (driverID == nil || $0.id == driverID) && (team == nil || $0.team == team) }
    }
    static func teams(in drivers: [LiveDriverTiming]) -> [String] { Array(Set(drivers.map(\.team))).sorted() }
    mutating func reconcile(with drivers: [LiveDriverTiming]) {
        if let team, !drivers.contains(where: { $0.team == team }) { self.team = nil }
        if let driverID, !drivers.contains(where: { $0.id == driverID && (team == nil || $0.team == team) }) { self.driverID = nil }
    }
}

enum LiveFastestLap {
    static func driverIDs(in drivers: [LiveDriverTiming]) -> Set<String> {
        let times = drivers.compactMap { driver -> (String, Double)? in
            guard let time = driver.bestLap.flatMap(LapDuration.seconds), time > 0 else { return nil }
            return (driver.id, time)
        }
        guard let fastest = times.map(\.1).min() else { return [] }
        return Set(times.filter { $0.1 == fastest }.map(\.0))
    }
}

/// Display-only full-distance projection; never used for championship standings.
/// Scales: https://www.formula1.com/en/latest/article/the-beginners-guide-to-the-formula-1-weekend.5RFZzGXNhEi9AEuMXwo987
enum LiveProjectedPoints {
    static func points(position: Int?, session: String?, retired: Bool) -> Int? {
        guard !retired, let position, position > 0 else { return nil }
        let scale: [Int]
        switch session?.lowercased() {
        case "race": scale = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
        case "sprint": scale = [8, 7, 6, 5, 4, 3, 2, 1]
        default: return nil
        }
        return position <= scale.count ? scale[position - 1] : 0
    }
}

struct LiveTimingRows: View {
    let drivers: [LiveDriverTiming]
    let selectedDriver: String?
    let select: (String) -> Void
    let availableWidth: CGFloat
    var fastestDriverIDs: Set<String> = []
    var sessionName: String? = nil
    var simulate: (() -> Void)? = nil
    @State private var showsIntervals = false
    @State private var fastestLapDriver: String?
    private var gapHelp: String {
        showsIntervals ? "Interval to the driver ahead. Click to show gap to leader." : "Gap to leader. Click to show interval to the driver ahead."
    }
    private var driverWidth: CGFloat { min(170, max(110, availableWidth * 0.14)) }
    // Numeric columns, gaps and horizontal padding retain their widths. Extra
    // window space goes to tyre history, immediately after the driver column.
    private var historyWidth: CGFloat { max(240, availableWidth - driverWidth - 430) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Pos").frame(width: 28, alignment: .leading)
                Text("Driver").frame(width: driverWidth, alignment: .leading)
                HStack(spacing: 4) {
                    Text("Pts*")
                    Button { simulate?() } label: {
                        Text("Simulate").font(.caption2.weight(.medium))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(.white, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.15)))
                    }.buttonStyle(.plain).fixedSize()
                        .disabled(simulate == nil)
                        .opacity(simulate == nil ? 0.5 : 1)
                }.frame(width: 82, alignment: .leading).padding(.horizontal, 6)
                    .help("Projected full-distance points. Simulate driver and team standings with this result.")
                Text("Tyre history").frame(width: historyWidth, alignment: .leading)
                Button { showsIntervals.toggle() } label: {
                    HStack(spacing: 3) {
                        Text(showsIntervals ? "Interval" : "Gap")
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 8))
                    }.frame(width: 60, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(gapHelp)
                    .accessibilityLabel(showsIntervals ? "Interval to driver ahead" : "Gap to leader")
                    .accessibilityHint("Switch gap display for all drivers")
                Text("Last lap").frame(width: 76, alignment: .leading)
                Text("Laps").frame(width: 28, alignment: .leading)
                Text("Stops").frame(width: 32, alignment: .leading)
                Text("Pit").frame(width: 28, alignment: .leading)
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 12).background(.quaternary.opacity(0.35))
            ForEach(drivers) { driver in
                HStack(spacing: 8) {
                    Text(driver.position.map(String.init) ?? "—").frame(width: 28, alignment: .leading)
                    driverCell(driver)
                    Text(LiveProjectedPoints.points(position: driver.position, session: sessionName, retired: driver.retired).map(String.init) ?? "—")
                        .frame(width: 82, alignment: .leading).padding(.horizontal, 6)
                        .accessibilityLabel("Projected points: " + (LiveProjectedPoints.points(position: driver.position, session: sessionName, retired: driver.retired).map(String.init) ?? "unavailable"))
                    TyreHistorySummary(segments: driver.tyreHistory, driverName: driver.name, stints: driver.stints)
                        .frame(width: historyWidth, alignment: .leading)
                    Button { showsIntervals.toggle() } label: {
                        Text((showsIntervals ? driver.interval : driver.gap) ?? "—")
                            .frame(width: 60, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(gapHelp)
                        .accessibilityLabel("\(driver.name), \(showsIntervals ? "interval to driver ahead" : "gap to leader"), \((showsIntervals ? driver.interval : driver.gap) ?? "unavailable")")
                        .accessibilityHint("Switch gap display for all drivers")
                    Text(driver.lastLap ?? "—").frame(width: 76, alignment: .leading)
                    Text(driver.laps.map(String.init) ?? "—").frame(width: 28, alignment: .leading)
                    Text(driver.stops.map(String.init) ?? "—").frame(width: 32, alignment: .leading)
                    Text(driver.inPit ? "PIT" : driver.pitOut == true ? "OUT" : "—")
                        .foregroundStyle(driver.inPit ? Color.orange : driver.pitOut == true ? Color.green : Color.secondary)
                        .frame(width: 28, alignment: .leading)
                }.font(.callout).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(driver.retired ? Color.secondary.opacity(0.08) : selectedDriver == driver.id ? Presentation.accent.opacity(0.08) : Color.clear)
                    .disabled(driver.retired)
                    .saturation(driver.retired ? 0 : 1)
                    .opacity(driver.retired ? 0.45 : 1)
                Divider()
            }
        }.background(.background, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func driverCell(_ driver: LiveDriverTiming) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(Presentation.color(hex: driver.teamColor)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Button { select(driver.id) } label: {
                        Text(driver.name).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Show timing details for \(driver.name)")
                        .accessibilityAddTraits(selectedDriver == driver.id ? [.isSelected] : [])
                    if fastestDriverIDs.contains(driver.id) {
                        Button { fastestLapDriver = driver.id } label: {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color(red: 0.40, green: 0.16, blue: 0.65), in: Circle())
                        }.buttonStyle(.plain)
                            .help("Show fastest lap · \(driver.bestLap ?? "—")")
                            .accessibilityLabel("Show fastest lap for \(driver.name)")
                            .popover(isPresented: Binding(get: { fastestLapDriver == driver.id }, set: { if !$0 { fastestLapDriver = nil } })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Fastest lap", systemImage: "stopwatch").font(.headline)
                                    Text(driver.name).foregroundStyle(.secondary)
                                    Text(driver.bestLap ?? "—").font(.title.bold()).monospacedDigit()
                                    Text("Best lap reported for this session snapshot")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(18)
                            }
                    }
                }
                Text(driver.retired ? "Retired" : driver.inPit ? "In pit lane" : driver.pitOut == true ? "Out lap" : driver.knockedOut ? "Knocked out" : driver.team)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(width: driverWidth, alignment: .leading)
    }

}
