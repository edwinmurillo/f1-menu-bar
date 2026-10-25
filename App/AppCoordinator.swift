import AppKit
import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case calendar, drivers, constructors, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .drivers: "person.crop.circle"
        case .constructors: "flag.checkered"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor @Observable
final class AppCoordinator {
    var section: AppSection = .calendar
    var selectedMeetingID: Int?
    var navigationRevision = 0
    func show(_ section: AppSection, meetingID: Int? = nil, openWindow: OpenWindowAction) {
        self.section = section
        if let meetingID { selectedMeetingID = meetingID }
        navigationRevision += 1
        openWindow(id: "championship")
        NSApp.activate(ignoringOtherApps: true)
    }
    func quit() { NSApplication.shared.terminate(nil) }
}
