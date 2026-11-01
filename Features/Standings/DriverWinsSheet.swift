import F1Core
import SwiftUI

struct DriverWinsSheet: View {
    let driver: DriverStanding
    let snapshot: SeasonSnapshot
    let timeZone: TimeZone
    @Environment(\.dismiss) private var dismiss
    private var victories: [WeekendVictory] {
        SeasonWinPresentation.newestFirst(SeasonStatistics.victories(for: driver, in: snapshot))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Season wins").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(driver.name).font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Text("\(String(snapshot.year)) season · \(driver.team)")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("Championship position \(driver.positionText ?? driver.position.map(String.init) ?? "—") · \(driver.points.formatted(.number.precision(.fractionLength(0...2)))) points")
                            .font(.callout).monospacedDigit()
                        if let context = snapshot.driverContext {
                            Text("After \(context.meetingName) · Updated \(updated(context.updatedAt))")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 24) {
                        total("Qualifying wins", count: snapshot.qualifyingUpdatedAt == nil ? nil : victories.filter(\.qualifying).count)
                        total("Grand Prix wins", count: snapshot.resultsUpdatedAt == nil ? nil : victories.filter(\.grandPrix).count)
                        total("Winning weekends", count: victories.count)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                    Text("Newest first · Quali means P1 in Grand Prix qualifying, before grid penalties. Sprint results are excluded.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if snapshot.issues[.results] != nil || snapshot.issues[.qualifying] != nil {
                        IssueBanner(message: "Some results could not be refreshed. Saved wins are shown; the history may be incomplete.")
                    }
                    if victories.isEmpty {
                        Text(snapshot.resultsUpdatedAt == nil || snapshot.qualifyingUpdatedAt == nil ? "Results pending" : "No wins yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(victories) { victory in
                        event(victory)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Published results · \(Presentation.providerName(snapshot.provider))")
                        Text("GP results updated: \(updated(snapshot.resultsUpdatedAt))")
                        Text("Qualifying results updated: \(updated(snapshot.qualifyingUpdatedAt))")
                        Text("Times shown in \(timeZone.identifier)")
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(width: 660, height: 640)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private func total(_ title: String, count: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count.map(String.init) ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func event(_ victory: WeekendVictory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(SeasonWinPresentation.flag(country: victory.weekend.country)).font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(victory.weekend.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text([victory.weekend.circuit, victory.weekend.location, victory.weekend.country]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if victory.qualifying {
                result("Qualifying · P1", winner: victory.weekend.qualifyingWinner,
                    session: victory.weekend.sessions.first(where: \.isQualifying))
            }
            if victory.grandPrix {
                result("Grand Prix · Winner", winner: victory.weekend.winner, session: victory.weekend.grandPrix)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func result(_ title: String, winner: RaceWinner?, session: RaceSession?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(Presentation.accent)
            Text(session?.start.map { Presentation.date($0, format: "EEE d MMM yyyy jmm", zone: timeZone) } ?? "Session date/time unavailable")
                .font(.callout).monospacedDigit()
            Text(winner.flatMap { $0.team.isEmpty ? nil : "Team at this event: \($0.team)" } ?? "Team at this event unavailable")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }

    private func updated(_ date: Date?) -> String {
        date.map { Presentation.date($0, format: "d MMM yyyy jmm", zone: timeZone) } ?? "Awaiting results"
    }
}
