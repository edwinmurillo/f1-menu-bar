import F1Core
import SwiftUI

struct StandingsView: View {
    let snapshot: SeasonSnapshot
    let drivers: Bool
    let loading: Bool
    let now: Date
    let timeZone: TimeZone
    private var context: ChampionshipContext? { drivers ? snapshot.driverContext : snapshot.constructorContext }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
            GeometryReader { viewport in
                if drivers && !snapshot.drivers.isEmpty {
                    Table(snapshot.drivers) {
                        TableColumn("Pos") { row in Text(row.positionText ?? row.position.map(String.init) ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(40)
                        TableColumn("Driver") { row in
                            standingName(row.name, subtitle: row.team, color: row.teamColor)
                        }.width(min: 160, ideal: 210)
                        TableColumn("Points") { row in points(row.points) }.width(65).alignment(.trailing)
                        TableColumn("Season wins") { row in
                            SeasonWinsView(victories: SeasonStatistics.victories(for: row, in: snapshot), drivers: true,
                                qualifyingAvailable: snapshot.qualifyingUpdatedAt != nil, racesAvailable: snapshot.resultsUpdatedAt != nil)
                        }.width(min: 300, ideal: 370)
                    }.tableStyle(.inset(alternatesRowBackgrounds: false)).frame(width: viewport.size.width, height: viewport.size.height)
                } else if !drivers && !snapshot.constructors.isEmpty {
                    Table(snapshot.constructors) {
                        TableColumn("Pos") { row in Text(row.positionText ?? row.position.map(String.init) ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(40)
                        TableColumn("Constructor") { row in
                            standingName(row.name, subtitle: row.drivers, color: row.color)
                        }.width(min: 160, ideal: 210)
                        TableColumn("Points") { row in points(row.points) }.width(65).alignment(.trailing)
                        TableColumn("GP wins") { row in
                            SeasonWinsView(victories: SeasonStatistics.victories(for: row, in: snapshot), drivers: false,
                                qualifyingAvailable: false, racesAvailable: snapshot.resultsUpdatedAt != nil)
                        }.width(min: 260, ideal: 370)
                    }.tableStyle(.inset(alternatesRowBackgrounds: false)).frame(width: viewport.size.width, height: viewport.size.height)
                } else {
                    ContentUnavailableView(loading ? "Loading championship points" : "Standings not available yet",
                        systemImage: "trophy", description: Text("Published points appear after a completed Grand Prix."))
                }
            }
            Text(drivers ? "Quali = P1 in Grand Prix qualifying · Scroll the win badges to see every event" : "Grand Prix wins by either driver · Hover a flag for the event")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                Text("Published championship points · \(Presentation.providerName(snapshot.provider))\(snapshot.provider == .openF1 ? " beta" : "")")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(26)
    }

    private func standingName(_ name: String, subtitle: String, color: String?) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Presentation.color(hex: color)).frame(width: 3, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 13, weight: .medium))
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 9).accessibilityElement(children: .combine)
    }
    private func points(_ points: Double) -> some View {
        Text(points.formatted(.number.precision(.fractionLength(0...2))))
            .font(.system(size: 16, weight: .semibold)).monospacedDigit()
    }
}
