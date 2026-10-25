import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor @Observable
final class AppPreferences {
    private let defaults: UserDefaults
    var showCountdown: Bool { didSet { defaults.set(showCountdown, forKey: "showCountdown") } }
    var useUTC: Bool { didSet { defaults.set(useUTC, forKey: "useUTC") } }
    var appearance: String { didSet { defaults.set(appearance, forKey: "appearance") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? true
        useUTC = defaults.bool(forKey: "useUTC")
        appearance = defaults.string(forKey: "appearance") ?? "system"
    }
    var timeZone: TimeZone { useUTC ? TimeZone(secondsFromGMT: 0)! : .autoupdatingCurrent }
    var timeZoneLabel: String { useUTC ? "UTC" : timeZone.identifier }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
}

@MainActor @Observable
final class LoginItemController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = error.localizedDescription }
        status = SMAppService.mainApp.status
    }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
