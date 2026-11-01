import F1Core
import Foundation
import SwiftUI

struct StandingsSimulation: Identifiable {
    struct Row: Identifiable {
        let id: String
        let name: String
        let current: Double
        let added: Int
        var isChampion = false
        var total: Double { current + Double(added) }
    }
    let id = UUID()
    let session: String
    let drivers: [Row]
    let teams: [Row]
    let notes: [String]

    static func make(season: SeasonSnapshot, timing: LiveTimingSnapshot) -> Self {
        var notes = ["Full-distance projection. Penalties and final classification may change the award. Equal totals retain the published order."]
        let name = timing.sessionName ?? "Unknown session"
        let weekend = season.weekends.first { $0.name.caseInsensitiveCompare(timing.meetingName ?? "") == .orderedSame }
        let selected = weekend?.sessions.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let eligible = name.lowercased() == "race" || name.lowercased() == "sprint"
        var driverAdds: [String: Int] = [:]
        var teamAdds: [String: Int] = [:]
        if !eligible { notes.append("This session does not award race or sprint points.") }
        func included(_ context: ChampionshipContext?) -> Bool {
            guard let context, let weekend, context.meetingName.caseInsensitiveCompare(weekend.name) == .orderedSame else { return false }
            return context.sessionID == selected?.id || context.sessionID == weekend.grandPrix?.id
        }
        let driverIncluded = included(season.driverContext)
        let teamIncluded = included(season.constructorContext)
        if driverIncluded { notes.append("The driver standings already include this session; no points are added again.") }
        if teamIncluded { notes.append("The team standings already include this session; no points are added again.") }
        // The stream has no championship IDs. Join driver numbers only within the
        // supplied season, then use that provider snapshot's constructor roster.
        let yearMatches = timing.receivedAt.map {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar.component(.year, from: $0) == season.year
        } ?? false
        let canProject = eligible && yearMatches && selected != nil
        if eligible && !canProject { notes.append("The stream could not be matched to this season/session; totals are unchanged.") }
        if canProject {
            for driver in timing.drivers {
                guard !driver.isOutOfRunning, let points = LiveProjectedPoints.points(position: driver.position, session: name, retired: driver.retired), points > 0 else { continue }
                let matches = season.drivers.filter { $0.driverNumber == Int(driver.id) }
                guard matches.count == 1, let standing = matches.first else {
                    notes.append("Could not match \(driver.name) to the championship roster; \(points) points are unassigned.")
                    continue
                }
                if !driverIncluded { driverAdds[standing.id, default: 0] += points }
                let teams = season.constructors.filter { $0.name.caseInsensitiveCompare(standing.team) == .orderedSame }
                if !teamIncluded {
                    if teams.count == 1, let team = teams.first { teamAdds[team.id, default: 0] += points }
                    else { notes.append("Could not match \(standing.team) to a constructor; \(points) team points are unassigned.") }
                }
            }
        }
        func sorted(_ rows: [Row]) -> [Row] {
            rows.enumerated().sorted { a, b in
                a.element.total == b.element.total ? a.offset < b.offset : a.element.total > b.element.total
            }.map(\.element)
        }
        if let context = season.driverContext { notes.append("Driver baseline: after \(context.meetingName).") }
        if let context = season.constructorContext { notes.append("Team baseline: after \(context.meetingName).") }
        var driverRows = sorted(season.drivers.map { Row(id: $0.id, name: $0.name, current: $0.points, added: driverAdds[$0.id] ?? 0) })
        var teamRows = sorted(season.constructors.map { Row(id: $0.id, name: $0.name, current: $0.points, added: teamAdds[$0.id] ?? 0) })
        let projected = weekend.map { RaceHistoryRequest(weekend: $0, provider: season.provider, sessionID: selected?.id) }
        let completeProjection = canProject && !notes.contains { $0.contains("unassigned") }
        func champion(_ rows: [Row], context: ChampionshipContext?, teams: Bool) -> String? {
            guard completeProjection, season.issues[teams ? .constructors : .drivers] == nil else { return nil }
            return ChampionshipClinchPolicy.championID(scores: rows.map { .init(id: $0.id, points: $0.total) },
                remainingPoints: ChampionshipClinchPolicy.remainingPoints(in: season, context: context, constructors: teams, projectedSession: projected))
        }
        let driverChampion = champion(driverRows, context: season.driverContext, teams: false)
        let teamChampion = champion(teamRows, context: season.constructorContext, teams: true)
        for i in driverRows.indices { driverRows[i].isChampion = driverRows[i].id == driverChampion }
        for i in teamRows.indices { teamRows[i].isChampion = teamRows[i].id == teamChampion }
        notes.append("Gold trophy = title secured on points with this projection and the published calendar. Possible ties are not marked; unresolved scoring sessions remain in the maximum available points.")
        return Self(session: [timing.meetingName, timing.sessionName, timing.currentLap.map { "Lap \($0)" }].compactMap { $0 }.joined(separator: " · "),
            drivers: driverRows, teams: teamRows, notes: notes)
    }
}

struct StandingsSimulationSheet: View {
    let simulation: StandingsSimulation
    @State private var showsTeams = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Simulated standings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text(simulation.session).foregroundStyle(.secondary)
            Picker("Standings", selection: $showsTeams) {
                Text("Drivers").tag(false)
                Text("Teams").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
            simulationTab(showsTeams ? "Teams" : "Drivers", rows: showsTeams ? simulation.teams : simulation.drivers)
                .id(showsTeams)
        }.padding(24).frame(width: 700, height: 650)
            .background(Color(nsColor: .windowBackgroundColor)).tint(Color.primary)
    }
    private func simulationTab(_ title: String, rows: [StandingsSimulation.Row]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                standings(title, rows: rows)
                ForEach(Array(simulation.notes.enumerated()), id: \.offset) { _, note in
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(14)
        }
    }

    private func standings(_ title: String, rows: [StandingsSimulation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            HStack {
                Text(title == "Drivers" ? "Driver" : "Team").frame(maxWidth: .infinity, alignment: .leading)
                Text("Current").frame(width: 90, alignment: .trailing)
                Text("+ Result").frame(width: 80, alignment: .trailing)
                Text("New total").frame(width: 90, alignment: .trailing)
            }.font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty { Text("Published standings are unavailable.").foregroundStyle(.secondary) }
            ForEach(rows) { row in
                HStack {
                    HStack(spacing: 6) {
                        Text(row.name)
                        if row.isChampion { ChampionshipTrophy(projected: true) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.current.formatted()).frame(width: 90, alignment: .trailing)
                    Text("+\(row.added)").frame(width: 80, alignment: .trailing)
                    Text(row.total.formatted()).fontWeight(.semibold).frame(width: 90, alignment: .trailing)
                }.monospacedDigit().padding(.vertical, 5)
                Divider()
            }
        }
    }
}
