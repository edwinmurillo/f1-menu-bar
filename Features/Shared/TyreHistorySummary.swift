import F1Core
import SwiftUI

struct TyreHistorySummary: View {
    let segments: [TyreHistorySegment]
    let driverName: String
    var stints: [LiveTyreStint] = []
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TyreHistoryLabel(segments: Array(segments.suffix(4)))
            if segments.count > 4 {
                HStack(spacing: 10) {
                    Text("Latest 4 of \(segments.count)").foregroundStyle(.secondary)
                    Button("See more") { showsAll = true }
                        .accessibilityLabel("See all \(segments.count) tyre stints for \(driverName)")
                }.font(.caption)
            }
        }
        .sheet(isPresented: $showsAll) {
            TyreHistorySheet(driverName: driverName, segments: segments, stints: stints)
        }
    }
}

struct TyreHistorySheet: View {
    let driverName: String
    let segments: [TyreHistorySegment]
    var stints: [LiveTyreStint] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tyre history").font(.title2.weight(.semibold))
                    Text(driverName).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Lap counts are laps driven on each set, not the race lap when it was fitted. The current stint has no final count.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(segments.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 16) {
                            Text("Stint \(index + 1)").foregroundStyle(.secondary).frame(width: 55, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                TyreLabel(compound: segments[index].compound)
                                if let stint = stints.sorted(by: { $0.id < $1.id }).dropFirst(index).first {
                                    if let isNew = stint.isNew { Text(isNew ? "New set" : "Used set").font(.caption).foregroundStyle(.secondary) }
                                    if let age = stint.initialAge { Text("Age when fitted: \(age) laps").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            Spacer()
                            Text(segments[index].completedLaps.map { "Laps \($0)" } ?? (index == segments.count - 1 ? "Current" : "Lap count unknown"))
                                .monospacedDigit()
                        }.padding(.vertical, 12)
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(width: 480, height: 520)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
