import F1Core
import SwiftUI

struct LiveSessionClockView: View {
    let store: LiveTimingStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let state = store.state
            if state.phase == .connected, state.snapshot.sessionStatus == "Started",
               let clock = state.snapshot.sessionClock {
                let remaining = Int(ceil(clock.remaining(at: tick.date)))
                let urgent = state.snapshot.sessionName?.localizedCaseInsensitiveContains("Practice") == true && remaining < 300
                HStack(spacing: 7) {
                    Image(systemName: "clock")
                    Text(clock.extrapolating ? "Time remaining" : "Clock paused")
                    Text(Self.format(remaining)).fontWeight(.semibold).monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(urgent ? Color.red : Color.primary)
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func format(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}
