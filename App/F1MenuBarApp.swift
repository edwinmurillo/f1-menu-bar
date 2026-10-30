import AppKit
import F1Core
import SwiftUI

@main @MainActor
struct F1MenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var store: SeasonStore
    @State private var historyStore: RaceHistoryStore
    @State private var liveStore: LiveTimingStore
    @State private var preferences = AppPreferences()
    @State private var coordinator = AppCoordinator()
    @State private var loginItem = LoginItemController()

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "F1MenuBar", directoryHint: .isDirectory)
        let openF1 = OpenF1Client()
        let jolpica = JolpicaClient()
        let repository = FallbackSeasonRepository(
            primary: OpenF1Repository(client: openF1, cache: SnapshotCache(directory: directory)),
            fallback: JolpicaRepository(client: jolpica, cache: SnapshotCache(directory: directory, provider: .jolpica)))
        let store = SeasonStore(repository: repository)
        _store = State(initialValue: store)
        _historyStore = State(initialValue: RaceHistoryStore(repository: HistoricalRaceRepository(
            openF1: openF1, jolpica: jolpica, cache: RaceHistoryCache(directory: directory))))
        let liveStore = LiveTimingStore(feed: F1LiveTimingClient(), archive: LiveLapArchive(directory: directory))
        _liveStore = State(initialValue: liveStore)
        lifecycle.store = store
        lifecycle.liveStore = liveStore
    }

    var body: some Scene {
        MenuBarExtra {
            NextWeekendView(store: store, preferences: preferences, coordinator: coordinator)
                .preferredColorScheme(preferences.colorScheme)
        } label: {
            Label(menuBarTitle, systemImage: "flag.checkered")
        }
        .menuBarExtraStyle(.window)

        // Keep the menu bar scene first; this auxiliary window opens on demand.
        Window("F1 Menu Bar", id: "championship") {
            ChampionshipWindow(store: store, liveStore: liveStore, historyStore: historyStore, preferences: preferences, coordinator: coordinator, loginItem: loginItem)
                .preferredColorScheme(preferences.colorScheme)
                .frame(minWidth: 1000, minHeight: 720)
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("Refresh data") { Task { await store.refresh(force: true) } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.isRefreshing)
            }
        }
    }

    private var menuBarTitle: String {
        guard preferences.showCountdown, let weekend = store.featured,
              let session = store.policy.nextSession(in: weekend, now: store.now), let start = session.start else {
            return "F1"
        }
        return "\(Presentation.shortSession(session.name)) \(Presentation.countdown(until: start, now: store.now))"
    }
}
