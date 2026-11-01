import F1Core
import SwiftUI

struct StandingsView: View {
    let snapshot: SeasonSnapshot
    let drivers: Bool
    let loading: Bool
    let now: Date
    let timeZone: TimeZone
    @State private var selectedWinsDriver: DriverStanding?
    private var context: ChampionshipContext? { drivers ? snapshot.driverContext : snapshot.constructorContext }

    private var championID: String? {
        let section: DataSection = drivers ? .drivers : .constructors
        guard snapshot.issues[section] == nil else { return nil }
        let scores = drivers
            ? snapshot.drivers.map { ChampionshipClinchPolicy.Score(id: $0.id, points: $0.points) }
            : snapshot.constructors.map { ChampionshipClinchPolicy.Score(id: $0.id, points: $0.points) }
        return ChampionshipClinchPolicy.championID(scores: scores,
            remainingPoints: ChampionshipClinchPolicy.remainingPoints(in: snapshot, context: context, constructors: !drivers))
    }

    var body: some View {
        Group {
            if drivers {
                GeometryReader { viewport in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            if snapshot.drivers.isEmpty {
                                emptyState.frame(maxWidth: .infinity, minHeight: 260)
                            } else {
                                driverRows(availableWidth: viewport.size.width - 52)
                            }
                            footer
                        }.padding(26).frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                    }
                }
            } else {
                constructorContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedWinsDriver) { driver in
            DriverWinsSheet(driver: snapshot.drivers.first { $0.id == driver.id } ?? driver,
                snapshot: snapshot, timeZone: timeZone)
        }
        .onChange(of: snapshot.year) { _, _ in selectedWinsDriver = nil }
    }

    @ViewBuilder private var header: some View {
        SectionHeader(title: drivers ? "Driver standings" : "Constructor standings",
            subtitle: "\(String(snapshot.year)) championship" + (context.map { " · After \($0.meetingName)" } ?? ""))
        if SchedulePolicy().isAwaitingStandings(in: snapshot.weekends, context: context, now: now, timeZone: timeZone) {
            Label("Waiting for this weekend’s results", systemImage: "clock")
                .font(.callout).foregroundStyle(.secondary)
        }
        if let issue = snapshot.issues[drivers ? .drivers : .constructors] { IssueBanner(message: issue) }
        if snapshot.issues[.results] != nil || (drivers && snapshot.issues[.qualifying] != nil) {
            IssueBanner(message: "Some season wins could not be refreshed. Saved results are shown when available.")
        }
    }

    private func driverRows(availableWidth: CGFloat) -> some View {
        let driverWidth = min(230, max(165, availableWidth * 0.22))
        let winsWidth = max(0, availableWidth - driverWidth - 177)
        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Pos").frame(width: 36, alignment: .leading)
                Text("Driver").frame(width: driverWidth, alignment: .leading)
                Text("Points").frame(width: 65, alignment: .trailing)
                Text("Season wins").frame(width: winsWidth, alignment: .leading)
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(14).background(.quaternary.opacity(0.35))
            ForEach(snapshot.drivers) { row in
                HStack(alignment: .top, spacing: 16) {
                    Text(row.positionText ?? row.position.map(String.init) ?? "—")
                        .monospacedDigit().foregroundStyle(.secondary).padding(.top, 9)
                        .frame(width: 36, alignment: .leading)
                    standingName(row.name, subtitle: row.team, color: row.teamColor, number: row.driverNumber.map(String.init) ?? "—", champion: championID == row.id)
                        .frame(width: driverWidth, alignment: .leading)
                    points(row.points).padding(.top, 6).frame(width: 65, alignment: .trailing)
                    SeasonWinsView(victories: SeasonStatistics.victories(for: row, in: snapshot), drivers: true,
                        qualifyingAvailable: snapshot.qualifyingUpdatedAt != nil, racesAvailable: snapshot.resultsUpdatedAt != nil,
                        driverName: row.name, showAll: { selectedWinsDriver = row })
                        .frame(width: winsWidth, alignment: .leading)
                }.padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
            }
        }.background(.background, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var constructorContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            GeometryReader { viewport in
                if !snapshot.constructors.isEmpty {
                    Table(snapshot.constructors) {
                        TableColumn("Pos") { row in Text(row.positionText ?? row.position.map(String.init) ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(40)
                        TableColumn("Constructor") { row in
                            standingName(row.name, subtitle: row.drivers, color: row.color, champion: championID == row.id)
                        }.width(min: 160, ideal: 210)
                        TableColumn("Points") { row in points(row.points) }.width(65).alignment(.trailing)
                        TableColumn("GP wins") { row in
                            SeasonWinsView(victories: SeasonStatistics.victories(for: row, in: snapshot), drivers: false,
                                qualifyingAvailable: false, racesAvailable: snapshot.resultsUpdatedAt != nil)
                        }.width(min: 260, ideal: 370)
                    }.tableStyle(.inset(alternatesRowBackgrounds: false)).frame(width: viewport.size.width, height: viewport.size.height)
                } else {
                    emptyState
                }
            }
            footer
        }.padding(26)
    }

    private var emptyState: some View {
        ContentUnavailableView(loading ? "Loading championship points" : "Standings not available yet",
            systemImage: "trophy", description: Text("Published points appear after a completed Grand Prix."))
    }

    @ViewBuilder private var footer: some View {
        Text(drivers ? "Quali = P1 in Grand Prix qualifying · Widen the window to see more wins · Click a pill for full details" : "Grand Prix wins by either driver · Hover a flag for the event")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
            Text("Published championship points · \(Presentation.providerName(snapshot.provider))\(snapshot.provider == .openF1 ? " beta" : "")")
        }.font(.caption).foregroundStyle(.secondary)
    }

    private func standingName(_ name: String, subtitle: String, color: String?, number: String? = nil, champion: Bool = false) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Presentation.color(hex: color)).frame(width: 3, height: 28).accessibilityHidden(true)
            if let number {
                Text(number).font(.callout.weight(.semibold)).monospacedDigit()
                    .frame(width: 25).accessibilityLabel("Racing number \(number)")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(name).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    if champion { ChampionshipTrophy(projected: false) }
                }
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }.padding(.vertical, 9).accessibilityElement(children: .combine)
    }
    private func points(_ points: Double) -> some View {
        Text(points.formatted(.number.precision(.fractionLength(0...2))))
            .font(.system(size: 16, weight: .semibold)).monospacedDigit()
    }
}
