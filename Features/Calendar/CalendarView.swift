import F1Core
import SwiftUI

struct CalendarView: View {
    let store: SeasonStore
    let preferences: AppPreferences
    @Bindable var coordinator: AppCoordinator
    var liveStore: LiveTimingStore? = nil
    @State private var selectedID: Int?

    private var snapshot: SeasonSnapshot { store.visibleSnapshot }
    private var selected: RaceWeekend? { snapshot.weekends.first { $0.id == selectedID } }
    private var months: [(String, [RaceWeekend])] {
        var groups: [(String, [RaceWeekend])] = []
        for weekend in snapshot.weekends {
            let title = Presentation.date(weekend.grandPrix?.start ?? weekend.firstStart, format: "MMMM", zone: preferences.timeZone)
            if groups.last?.0 == title { groups[groups.count - 1].1.append(weekend) }
            else { groups.append((title, [weekend])) }
        }
        return groups
    }

    var body: some View {
        GeometryReader { viewport in
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "Season calendar", subtitle: "\(String(snapshot.year)) · \(Presentation.providerName(snapshot.provider))")
                if let issue = snapshot.issues[.schedule] ?? snapshot.issues[.results] { IssueBanner(message: issue) }
                if snapshot.weekends.isEmpty {
                    ContentUnavailableView(store.isRefreshing ? "Loading the calendar" : "Calendar not available", systemImage: "calendar", description: Text("Race weekends will appear when the season is published."))
                } else {
                    HStack(alignment: .top, spacing: 22) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(months.enumerated()), id: \.offset) { _, month in
                                        Text(month.0.uppercased()).font(.system(size: 11, weight: .semibold))
                                            .tracking(0.9).foregroundStyle(.secondary).padding(.top, 16).padding(.bottom, 8).padding(.leading, 9)
                                        ForEach(month.1) { weekend in
                                            Button { selectedID = weekend.id } label: {
                                                raceRow(weekend)
                                            }.buttonStyle(.plain).id(weekend.id)
                                        }
                                    }
                                }.padding(.trailing, 8)
                            }
                            .onChange(of: snapshot.weekends.map(\.id), initial: true) { _, _ in
                                selectDefault()
                                if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                            }
                            .onChange(of: coordinator.navigationRevision) { _, _ in
                                if let id = coordinator.selectedMeetingID, snapshot.weekends.contains(where: { $0.id == id }) {
                                    selectedID = id; proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }.frame(minWidth: 270, maxWidth: .infinity)
                        Divider()
                        ScrollView {
                            if let selected {
                                VStack(alignment: .leading, spacing: 16) {
                                    Button { coordinator.showTimeline(selected, provider: snapshot.provider, at: store.now) } label: {
                                        Label("View lap history", systemImage: "chart.xyaxis.line")
                                    }.buttonStyle(.borderedProminent)
                                        .disabled(!selected.hasStartedTimelineSession(at: store.now))
                                        .help("Open available session history")
                                        .accessibilityHint("Opens available session history for \(selected.name)")
                                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                                        WeekendDetailView(weekend: selected,
                                            status: store.policy.status(of: selected, in: snapshot.weekends, now: store.now),
                                            now: liveStore == nil ? store.now : clock.date, zone: preferences.timeZone,
                                            ongoing: store.policy.isOngoing(selected, now: store.now, timeZone: preferences.timeZone),
                                            liveSnapshot: liveStore?.state.snapshot)
                                    }
                                }
                            }
                        }.frame(width: 255)
                    }
                }
            }.padding(26)
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }
    }

    private func selectDefault() {
        if let requested = coordinator.selectedMeetingID, snapshot.weekends.contains(where: { $0.id == requested }) {
            selectedID = requested; return
        }
        if let selectedID, snapshot.weekends.contains(where: { $0.id == selectedID }) { return }
        selectedID = store.policy.featured(in: snapshot.weekends, now: store.now)?.id ?? snapshot.weekends.last?.id
    }

    private func raceRow(_ weekend: RaceWeekend) -> some View {
        let status = store.policy.status(of: weekend, in: snapshot.weekends, now: store.now)
        return HStack(spacing: 12) {
            Text(Presentation.date(weekend.grandPrix?.start ?? weekend.firstStart, format: "dd", zone: preferences.timeZone))
                .font(.system(size: 20, weight: .medium)).monospacedDigit().frame(width: 31)
            Text(SeasonWinPresentation.flag(country: weekend.country)).font(.title2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(weekend.name.replacingOccurrences(of: " Grand Prix", with: "")).fontWeight(.medium)
                    if weekend.hasSprint { Text("SPRINT").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
                }
                Text(weekend.circuit)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Group {
                if weekend.winner != nil || weekend.podium?.isEmpty == false {
                    CalendarPodium(weekend: weekend, compact: true)
                } else if store.policy.isOngoing(weekend, now: store.now, timeZone: preferences.timeZone) {
                    OngoingWeekendBadge()
                } else { StatusBadge(status: status) }
            }.frame(width: 130, alignment: .leading)
        }
        .padding(.vertical, 13).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedID == weekend.id ? Presentation.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selectedID == weekend.id ? [.isSelected] : [])
    }
}

struct WeekendDetailView: View {
    let weekend: RaceWeekend
    let status: WeekendStatus
    let now: Date
    let zone: TimeZone
    var ongoing = false
    var liveSnapshot: LiveTimingSnapshot? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "flag.checkered").font(.system(size: 22)).padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                if ongoing { OngoingWeekendBadge() } else { StatusBadge(status: status) }
                Text(weekend.name).font(.system(size: 21, weight: .semibold)).tracking(-0.4)
                Text([weekend.circuit, weekend.country].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                Text(Presentation.weekendDates(weekend, zone: zone)).font(.caption).foregroundStyle(.secondary)
            }
            if weekend.winner != nil || weekend.podium?.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GRAND PRIX PODIUM").font(.caption2).foregroundStyle(.secondary)
                    CalendarPodium(weekend: weekend, compact: false)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            } else if status == .resultsPending {
                IssueBanner(message: "The scheduled race start has passed. Waiting for a published classification.")
            } else if status == .unavailable {
                IssueBanner(message: "This event is missing from the latest calendar. Previously saved times are shown.")
            }
            SessionScheduleView(weekend: weekend, now: now, zone: zone, compact: true, showsSessionStatus: true, liveSnapshot: liveSnapshot)
            Divider()
            Label("All times in \(zone.identifier)", systemImage: "globe").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 2).padding(.top, 12)
    }
}

private struct OngoingWeekendBadge: View {
    var body: some View {
        Text("Ongoing").font(.caption.weight(.medium)).foregroundStyle(.green)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Color.green.opacity(0.12), in: Capsule())
            .accessibilityLabel("Ongoing Grand Prix weekend")
    }
}
