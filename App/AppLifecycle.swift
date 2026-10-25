import AppKit
import F1Core

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    var store: SeasonStore?
    var liveStore: LiveTimingStore?
    private var refreshTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?
    private var timeZoneObserver: (any NSObjectProtocol)?
    private var sleepObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let store else { return }
        // MenuBarExtra labels are extracted by SwiftUI, not ordinary view hosts.
        // Keep their content simple and own refresh work at application lifetime.
        refreshTask = Task {
            await store.start()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { break }
                await store.tick()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.liveStore?.resume(); await store.tick() } }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.liveStore?.suspend() } }
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { _ in Task { @MainActor in await store.tick() } }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        store?.cancelRefresh()
        liveStore?.stop()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let timeZoneObserver { NotificationCenter.default.removeObserver(timeZoneObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
    }
}
