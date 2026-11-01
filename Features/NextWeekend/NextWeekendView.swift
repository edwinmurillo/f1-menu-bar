import F1Core
import SwiftUI

struct NextWeekendView: View {
    let store: SeasonStore
    let preferences: AppPreferences
    let coordinator: AppCoordinator
    var liveStore: LiveTimingStore? = nil
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if let weekend = store.featured {
                weekendContent(weekend)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "flag.checkered").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(store.snapshot.weekends.isEmpty ? (store.isRefreshing ? "Finding the next Grand Prix" : "Calendar unavailable") : "Season complete")
                        .font(.title3.weight(.semibold))
                    if store.isRefreshing { ProgressView().controlSize(.small) }
                    else {
                        Text(store.snapshot.weekends.isEmpty ? "The calendar is not available yet. Try refreshing." : "The next calendar has not been published yet. You can still browse this season’s results.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }.padding(28).frame(maxWidth: .infinity)
            }

            if let issue = store.startupIssue ?? store.snapshot.issues[.schedule] {
                IssueBanner(message: issue).padding(.horizontal, 18).padding(.bottom, 12)
            }
            Divider()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        if let weekend = store.featured { store.displayYear = weekend.year }
                        coordinator.show(.calendar, meetingID: store.featured?.id, openWindow: openWindow)
                    } label: {
                        Label("Full calendar", systemImage: "calendar").frame(maxWidth: .infinity)
                    }
                    Button { coordinator.show(.drivers, openWindow: openWindow) } label: {
                        Label("Standings", systemImage: "trophy").frame(maxWidth: .infinity)
                    }
                }.buttonStyle(.bordered).controlSize(.regular)
                Button { coordinator.show(.live, openWindow: openWindow) } label: {
                    Label("Live timing", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.regular)
                HStack(spacing: 8) {
                    Label(preferences.timeZoneLabel, systemImage: "globe")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    if store.isRefreshing { ProgressView().controlSize(.mini).help("Refreshing race data") }
                    Button { Task { await store.refresh(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(store.isRefreshing).help("Refresh data").accessibilityLabel("Refresh data")
                    Button { coordinator.show(.settings, openWindow: openWindow) } label: {
                        Image(systemName: "slider.horizontal.3")
                    }.help("Settings").accessibilityLabel("Settings")
                    Button { coordinator.quit() } label: {
                        Image(systemName: "power")
                    }.help("Quit F1 Menu Bar").accessibilityLabel("Quit F1 Menu Bar")
                }.buttonStyle(.borderless)
                HStack {
                    Text(Presentation.providerName(store.snapshot.provider))
                    Spacer()
                    Text(store.isRefreshing ? "Refreshing…" : store.snapshot.latestUpdate.map { "Updated \(Presentation.date($0, format: "jmm", zone: preferences.timeZone))" } ?? "Waiting for data")
                }.font(.caption2).foregroundStyle(.tertiary)
            }.padding(16).background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 386)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color.primary)
        .onAppear { Task { await store.tick() } }
    }

    private func weekendContent(_ weekend: RaceWeekend) -> some View {
        let isOngoing = store.policy.isOngoing(weekend, now: store.now, timeZone: preferences.timeZone)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Capsule().fill(Presentation.accent).frame(width: 18, height: 4)
                    Text(isOngoing ? "ONGOING GRAND PRIX" : "NEXT GRAND PRIX")
                        .font(.system(size: 11, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(isOngoing ? Presentation.accent : Color.secondary)
                        .accessibilityLabel(isOngoing ? "Ongoing Grand Prix weekend" : "Next Grand Prix")
                    Spacer()
                    if weekend.hasSprint { Text("SPRINT").font(.caption2.weight(.semibold)).foregroundStyle(Presentation.accent) }
                }
                Text(weekend.name.replacingOccurrences(of: " Grand Prix", with: ""))
                    .font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text([weekend.circuit, weekend.country].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
                Label(Presentation.weekendDates(weekend, zone: preferences.timeZone), systemImage: "calendar")
                    .font(.callout)
            }
            Group {
                if let next = store.policy.nextSession(in: weekend, now: store.now), let start = next.start {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("NEXT SESSION").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(Presentation.session(next.name)).font(.callout.weight(.semibold))
                        }
                        Spacer()
                        Text(Presentation.countdown(until: start, now: store.now))
                            .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    }.padding(14).background(Presentation.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                } else if let start = weekend.grandPrix?.start, start <= store.now {
                    IssueBanner(message: "Race scheduled to have started · results pending")
                } else {
                    IssueBanner(message: "Session times have not been announced yet.")
                }
            }
            if let liveStore {
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    SessionScheduleView(weekend: weekend, now: clock.date, zone: preferences.timeZone,
                        showsSessionStatus: true, liveSnapshot: liveStore.state.snapshot)
                }
            } else {
                SessionScheduleView(weekend: weekend, now: store.now, zone: preferences.timeZone, showsSessionStatus: true)
            }
        }.padding(22)
    }
}
