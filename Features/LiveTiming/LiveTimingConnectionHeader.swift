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
                    if let track = state.snapshot.trackStatus {
                        Label(track, systemImage: "flag.fill")
                            .foregroundStyle(track.localizedCaseInsensitiveContains("clear") ? Color.blue :
                                track.localizedCaseInsensitiveContains("red") ? Color.red : Color.yellow)
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
