import F1Core
import SwiftUI

struct LiveTimingPlaceholder: View {
    let phase: LiveConnectionPhase
    let isRunning: Bool

    private var isLoading: Bool {
        isRunning && (phase == .connecting || phase == .connected || phase == .reconnecting)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: phase == .unavailable ? "wifi.exclamationmark" : "flag.checkered")
                .font(.system(size: 23, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(spacing: 7) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isLoading {
                TimingRowsSkeleton().frame(width: 296).padding(.top, 12)
                    .accessibilityHidden(true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch phase {
        case .connecting: "Connecting to live timing"
        case .reconnecting: "Reconnecting to live timing"
        case .connected: "Waiting for session timing"
        case .unavailable: "Live timing unavailable"
        case .stopped: "Connect to follow a session"
        }
    }

    private var detail: String {
        switch phase {
        case .connecting: "Getting the latest positions, laps and tyres."
        case .reconnecting: "Restoring the connection to the session feed."
        case .connected: "Timing will appear here when F1 publishes it."
        case .unavailable: "Use Connect to try again when the feed is available."
        case .stopped: "Choose Connect to see the latest session timing."
        }
    }
}

private struct TimingRowsSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if reduceMotion || scenePhase != .active {
            rows.foregroundStyle(.primary.opacity(0.12))
        } else {
            // Only this small decorative view redraws. The timing table and
            // connection state do not participate in the animation.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { clock in
                let phase = clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                let progress = (1 - cos(.pi * phase)) / 2
                rows.foregroundStyle(.primary.opacity(0.12))
                    .overlay {
                        GeometryReader { geometry in
                            LinearGradient(colors: [.clear, .primary.opacity(0.20), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geometry.size.width * 0.45)
                                .offset(x: geometry.size.width * (1.45 * progress - 0.45))
                        }.mask(rows)
                    }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 14) {
            ForEach([112, 86, 100], id: \.self) { nameWidth in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 18, height: 18)
                    Capsule().frame(width: CGFloat(nameWidth), height: 8)
                    Spacer(minLength: 12)
                    Capsule().frame(width: 40, height: 8)
                    Capsule().frame(width: 28, height: 12)
                }
            }
        }
    }
}
