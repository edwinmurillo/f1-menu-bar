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

struct LiveTimingRows: View {
    let drivers: [LiveDriverTiming]
    let selectedDriver: String?
    let select: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Pos").frame(width: 32, alignment: .leading)
                Text("Driver").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gap").frame(width: 66, alignment: .leading)
                Text("Last lap").frame(width: 86, alignment: .leading)
                Text("Laps").frame(width: 36, alignment: .leading)
                Text("Stops").frame(width: 36, alignment: .leading)
                Text("Pit").frame(width: 36, alignment: .leading)
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(12).background(.quaternary.opacity(0.35))
            ForEach(drivers) { driver in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(driver.position.map(String.init) ?? "—").frame(width: 32, alignment: .leading)
                        Button { select(driver.id) } label: {
                            HStack(spacing: 8) {
                                Capsule().fill(Presentation.color(hex: driver.teamColor)).frame(width: 3, height: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(driver.name).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                                    Text(driver.retired ? "Retired" : driver.inPit ? "In pit lane" : driver.pitOut == true ? "Out lap" : driver.knockedOut ? "Knocked out" : driver.team)
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Show timing details for \(driver.name)")
                            .accessibilityAddTraits(selectedDriver == driver.id ? [.isSelected] : [])
                        Text(driver.gap ?? "—").frame(width: 66, alignment: .leading)
                        Text(driver.lastLap ?? "—").frame(width: 86, alignment: .leading)
                        Text(driver.laps.map(String.init) ?? "—").frame(width: 36, alignment: .leading)
                        Text(driver.stops.map(String.init) ?? "—").frame(width: 36, alignment: .leading)
                        Text(driver.inPit ? "PIT" : driver.pitOut == true ? "OUT" : "—")
                            .foregroundStyle(driver.inPit ? Color.orange : driver.pitOut == true ? Color.green : Color.secondary)
                            .frame(width: 36, alignment: .leading)
                    }.font(.callout).monospacedDigit()
                    HStack(alignment: .top, spacing: 10) {
                        Text("Tyre history").font(.caption).foregroundStyle(.secondary).frame(width: 85, alignment: .leading)
                        TyreHistorySummary(segments: driver.tyreHistory, driverName: driver.name, stints: driver.stints)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedDriver == driver.id ? Presentation.accent.opacity(0.08) : Color.clear)
                Divider()
            }
        }.background(.background, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
