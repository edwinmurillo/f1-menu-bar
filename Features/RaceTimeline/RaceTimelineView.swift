import F1Core
import SwiftUI

struct RaceTimelineView: View {
    private enum Mode: String, CaseIterable { case recorded = "Recorded", demo = "Demo" }
    let store: LiveTimingStore
    let preferences: AppPreferences
    @State private var mode: Mode = .recorded

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Timeline mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
                Spacer()
                Text(mode == .recorded ? "Only captured laps" : "Simulated missing laps and events")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26).padding(.top, 20)
            LiveTimingConnectionHeader(store: store, preferences: preferences)
                .padding(.horizontal, 26)
            Divider()
            Group {
                switch mode {
                case .recorded: RecordedRaceTimelineView(store: store)
                case .demo: DemoRaceTimelineView(store: store)
                }
            }
            // Empty reconnect snapshots preserve the session; a known new identity
            // resets selection, highlights and replay before showing new data.
            .id(store.state.snapshot.sessionID ?? store.lapSnapshots.values.first?.sessionID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
