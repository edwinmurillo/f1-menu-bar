import F1Core
import SwiftUI

enum LiveTimingConnectionPresentation {
    static func isLive(_ state: LiveTimingState, at now: Date) -> Bool {
        state.phase == .connected && state.snapshot.hasFreshTiming(at: now)
    }

    static func status(_ state: LiveTimingState, at now: Date) -> String {
        switch state.phase {
        case .stopped: "Disconnected · last received data"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting · timing may be outdated"
        case .unavailable: "Live timing unavailable"
        case .connected:
            if isLive(state, at: now) { "Live" }
            else if state.snapshot.hasFinished { "Session finished · latest available timing" }
            else if state.snapshot.sessionStatus == "Aborted" { "Session suspended" }
            else if state.snapshot.lastTimingUpdate == nil { "Connected · waiting for fresh timing" }
            else { "No recent timing · data may be outdated" }
        }
    }
}

enum LiveTrackIndicator: Equatable {
    case clear, yellow, safetyCar, red, virtualSafetyCar, virtualSafetyCarEnding, pitExitClosed, pitExitOpen, unknown

    static func resolve(message: String?, code: String?, sessionStatus: String? = nil) -> Self {
        if sessionStatus == "Aborted" { return .red }
        func normalized(_ value: String?) -> String { (value ?? "").lowercased().filter { $0.isLetter || $0.isNumber } }
        let text = normalized(message)
        if text.contains("pitexitclosed") { return .pitExitClosed }
        if text.contains("pitexitopen") { return .pitExitOpen }
        switch normalized(code) {
        case "1": return .clear
        case "2": return .yellow
        case "4": return .safetyCar
        case "5": return .red
        case "6": return .virtualSafetyCar
        case "7": return .virtualSafetyCarEnding
        default: break
        }
        switch text {
        case "allclear", "clear", "green": return .clear
        case "yellow", "yellowflag", "doubleyellow": return .yellow
        case "scdeployed", "safetycardeployed": return .safetyCar
        case "red", "redflag": return .red
        case "vscdeployed", "virtualsafetycardeployed": return .virtualSafetyCar
        case "vscending", "virtualsafetycarending": return .virtualSafetyCarEnding
        default: return .unknown
        }
    }
    var title: String? {
        switch self {
        case .clear: "All Clear"
        case .yellow: "Yellow flag"
        case .safetyCar: "Safety Car deployed"
        case .red: "Red flag"
        case .virtualSafetyCar: "Virtual Safety Car deployed"
        case .virtualSafetyCarEnding: "Virtual Safety Car ending"
        case .pitExitClosed: "Pit exit closed"
        case .pitExitOpen: "Pit exit open"
        case .unknown: nil
        }
    }
    var color: Color {
        switch self {
        case .clear: .blue
        case .red, .pitExitClosed: .red
        case .yellow, .safetyCar, .virtualSafetyCar, .virtualSafetyCarEnding: .yellow
        case .pitExitOpen: .green
        case .unknown: .secondary
        }
    }
    var symbol: String {
        switch self {
        case .pitExitClosed, .pitExitOpen: "circle.fill"
        case .unknown: "questionmark.circle"
        default: "flag.fill"
        }
    }
}

struct LiveTimingConnectionHeader: View {
    let store: LiveTimingStore
    let preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text([store.state.snapshot.meetingName, store.state.snapshot.sessionName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button(store.isRunning ? "Disconnect" : "Connect") {
                    if store.isRunning { store.disconnect() } else { store.connect() }
                }.buttonStyle(.bordered)
            }
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                let state = store.state
                let live = LiveTimingConnectionPresentation.isLive(state, at: clock.date)
                HStack(spacing: 12) {
                    Label(LiveTimingConnectionPresentation.status(state, at: clock.date),
                          systemImage: live ? "dot.radiowaves.left.and.right" : "clock")
                        .foregroundStyle(live ? Color.green : Color.secondary)
                    if let lap = state.snapshot.currentLap {
                        Text(state.snapshot.totalLaps.map { "Lap \(lap) / \($0)" } ?? "Lap \(lap)")
                            .monospacedDigit()
                    }
                    if state.snapshot.trackStatus != nil || state.snapshot.trackStatusCode != nil || state.snapshot.sessionStatus == "Aborted" {
                        let indicator = LiveTrackIndicator.resolve(message: state.snapshot.trackStatus, code: state.snapshot.trackStatusCode, sessionStatus: state.snapshot.sessionStatus)
                        Label(indicator.title ?? state.snapshot.trackStatus ?? "Unknown track status", systemImage: indicator.symbol)
                            .foregroundStyle(indicator.color)
                    }
                    Spacer()
                    if let date = state.snapshot.receivedAt {
                        Text("Received \(Presentation.date(date, format: "jmmss", zone: preferences.timeZone))").font(.caption)
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }.font(.title3.weight(.semibold))
            }
            LiveSessionClockView(store: store)
            if let message = store.state.message {
                IssueBanner(message: message + (store.state.retryAt.map {
                    " Retry after \(Presentation.date($0, format: "jmmss", zone: preferences.timeZone))."
                } ?? ""))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
