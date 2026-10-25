import AppKit
import F1Core
import SwiftUI

@main @MainActor
struct F1MenuBarApp: App {
    @State private var store: SeasonStore
    @State private var preferences = AppPreferences()
    @State private var coordinator = AppCoordinator()
    @State private var loginItem = LoginItemController()

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "F1MenuBar", directoryHint: .isDirectory)
        let cache = SnapshotCache(directory: directory)
        let repository = OpenF1Repository(client: OpenF1Client(), cache: cache)
        _store = State(initialValue: SeasonStore(repository: repository))
    }

    var body: some Scene {
        MenuBarExtra {
            NextWeekendView(store: store, preferences: preferences, coordinator: coordinator)
                .preferredColorScheme(preferences.colorScheme)
        } label: {
            MenuBarLabel(store: store, preferences: preferences)
                .task {
                    await store.start()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) }
                        catch { break }
                        await store.tick()
                    }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    Task { await store.tick() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
                    Task { await store.tick() }
                }
        }
        .menuBarExtraStyle(.window)

        // Keep the menu bar scene first; this auxiliary window opens on demand.
        Window("F1 Menu Bar", id: "championship") {
            ChampionshipWindow(store: store, preferences: preferences, coordinator: coordinator, loginItem: loginItem)
                .preferredColorScheme(preferences.colorScheme)
                .frame(minWidth: 790, minHeight: 550)
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
}

private struct MenuBarLabel: View {
    let store: SeasonStore
    let preferences: AppPreferences
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                if preferences.showCountdown, let weekend = store.featured,
                   let session = store.policy.nextSession(in: weekend, now: context.date), let start = session.start {
                    Text("\(Presentation.shortSession(session.name)) \(Presentation.countdown(until: start, now: context.date))")
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("F1 Menu Bar. Open the next Grand Prix schedule")
        }
    }
}
