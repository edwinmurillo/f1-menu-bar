import F1Core
import OSLog
import SwiftUI

struct ChampionshipWindow: View {
    let store: SeasonStore
    let liveStore: LiveTimingStore
    let historyStore: RaceHistoryStore
    let preferences: AppPreferences
    @Bindable var coordinator: AppCoordinator
    let loginItem: LoginItemController
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isWindowVisible = false
    private let logger = Logger(subsystem: "com.murilloarturo.f1menubar", category: "Navigation")

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding<AppSection?>(get: { coordinator.section }, set: { if let value = $0 { coordinator.section = value } })) {
                Section("Championship") {
                    ForEach([AppSection.live, .calendar, .drivers, .constructors]) { section in
                        Label(section.title, systemImage: section.symbol).tag(section)
                    }
                }
                Section {
                    Label(AppSection.settings.title, systemImage: AppSection.settings.symbol).tag(AppSection.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 145, ideal: 165, max: 210)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch coordinator.section {
                    case .calendar: CalendarView(store: store, preferences: preferences, coordinator: coordinator)
                    case .drivers: StandingsView(snapshot: store.visibleSnapshot, drivers: true, loading: store.isRefreshing,
                        now: store.now, timeZone: preferences.timeZone)
                    case .constructors: StandingsView(snapshot: store.visibleSnapshot, drivers: false, loading: store.isRefreshing,
                        now: store.now, timeZone: preferences.timeZone)
                    case .live: LiveTimingView(store: liveStore, preferences: preferences, season: store, historyStore: historyStore, coordinator: coordinator)
                    case .settings: SettingsView(preferences: preferences, store: store, loginItem: loginItem)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                HStack(spacing: 8) {
                    Text(preferences.timeZoneLabel)
                    Text("·").accessibilityHidden(true)
                    Text(freshness)
                    Spacer()
                    if store.isRefreshing { ProgressView().controlSize(.mini) }
                    if coordinator.section == .live {
                        Text("Personal live connection")
                    } else { Link("OpenF1", destination: URL(string: "https://openf1.org/")!) }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowVisibilityReader { visible in
            isWindowVisible = visible
            liveStore.setVisible(visible && coordinator.section == .live)
        }.frame(width: 0, height: 0))
        .navigationTitle("F1 Menu Bar")
        .toolbar {
            if coordinator.section != .settings && coordinator.section != .live {
                ToolbarItem(placement: .principal) {
                    if store.availableSeasons.count > 1 {
                        Picker("Season", selection: Binding(get: { store.visibleSnapshot.year }, set: { store.displayYear = $0 })) {
                            ForEach(store.availableSeasons, id: \.year) { snapshot in Text(String(snapshot.year)).tag(snapshot.year) }
                        }.labelsHidden().frame(minWidth: 120)
                    } else {
                        Text("\(String(store.visibleSnapshot.year)) season")
                            .foregroundStyle(.secondary).fixedSize().padding(.horizontal, 8)
                    }
                }
            }
            if coordinator.section != .live {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await store.refresh(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .labelStyle(.iconOnly).frame(width: 32, height: 28)
                        .disabled(store.isRefreshing).help("Refresh data (⌘R)")
                }
            }
        }
        .tint(Color.primary)
        .onAppear {
            logger.info("Detail appeared section=\(coordinator.section.rawValue, privacy: .public)")
            Task { await store.tick() }
        }
        .onChange(of: coordinator.section) { _, section in
            logger.info("Navigate section=\(section.rawValue, privacy: .public) windowVisible=\(isWindowVisible)")
            columnVisibility = .all
            liveStore.setVisible(isWindowVisible && section == .live)
        }
        .onChange(of: coordinator.navigationRevision) { _, _ in columnVisibility = .all }
        .onDisappear {
            logger.info("Detail disappeared section=\(coordinator.section.rawValue, privacy: .public)")
            liveStore.setVisible(false)
            historyStore.cancel()
        }
    }

    private var freshness: String {
        if coordinator.section == .live { return "Timing is separate from published standings" }
        if store.isRefreshing { return "Refreshing…" }
        let snapshot = store.visibleSnapshot
        let date: Date?
        switch coordinator.section {
        case .drivers: date = snapshot.driverContext?.updatedAt
        case .constructors: date = snapshot.constructorContext?.updatedAt
        case .calendar, .settings, .live: date = snapshot.scheduleUpdatedAt
        }
        return date.map { "Updated \(Presentation.date($0, format: "d MMM jmm", zone: preferences.timeZone))" } ?? "Waiting for published data"
    }
}
