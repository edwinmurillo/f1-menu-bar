import AppKit
import F1Core
import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case calendar, drivers, constructors, live, timeline, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: "Live timing"
        case .timeline: "Race timeline"
        default: rawValue.capitalized
        }
    }
    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .drivers: "person.crop.circle"
        case .constructors: "flag.checkered"
        case .live: "dot.radiowaves.left.and.right"
        case .timeline: "chart.xyaxis.line"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor @Observable
final class AppCoordinator {
    var section: AppSection = .calendar
    var selectedMeetingID: Int?
    var timelineRequest: RaceHistoryRequest?

    func showTimeline(_ weekend: RaceWeekend, provider: DataProvider, at now: Date = Date()) {
        guard !weekend.isCancelled, !weekend.isMissingFromSchedule,
              weekend.activeSessions.contains(where: { ($0.start ?? .distantFuture) <= now }) else { return }
        timelineRequest = RaceHistoryRequest(weekend: weekend, provider: provider)
        section = .timeline
        navigationRevision += 1
    }
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
