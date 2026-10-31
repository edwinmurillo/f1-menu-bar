import F1Core
import SwiftUI

struct LiveTimingView: View {
    let store: LiveTimingStore
    let preferences: AppPreferences
    @State private var selectedDriver: String?
    @State private var filter = LiveTimingFilter()
    private var snapshot: LiveTimingSnapshot { store.state.snapshot }
    private var drivers: [LiveDriverTiming] { filter.apply(to: snapshot.drivers) }
    private var selected: LiveDriverTiming? {
        drivers.first { $0.id == selectedDriver } ?? drivers.first
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                content(minimumHeight: viewport.size.height)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: snapshot.sessionID) { _, _ in selectedDriver = nil; filter = LiveTimingFilter() }
        .onChange(of: snapshot.drivers.map { $0.id + ":" + $0.team }) { _, _ in
            filter.reconcile(with: snapshot.drivers)
        }
    }

    private func content(minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Live timing", subtitle: "Experimental personal connection")
            LiveTimingConnectionHeader(store: store, preferences: preferences)
            if snapshot.drivers.isEmpty {
                Spacer(minLength: 24)
                LiveTimingPlaceholder(phase: store.state.phase, isRunning: store.isRunning)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
            } else {
                filters
                if drivers.isEmpty {
                    ContentUnavailableView {
                        Label("No matching drivers", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Change the driver or team filter to see timing rows.")
                    } actions: {
                        Button("Clear filters") { filter = LiveTimingFilter() }
                    }
                } else {
                    LiveTimingRows(drivers: drivers, selectedDriver: selected?.id, select: { selectedDriver = $0 })
                    if let driver = selected { driverDetail(driver) }
                }
            }
            if !snapshot.messages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RACE CONTROL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(snapshot.messages) { message in
                        HStack(alignment: .top, spacing: 10) {
                            Text(message.date.map { Presentation.date($0, format: "jmmss", zone: preferences.timeZone) } ?? "—")
                                .foregroundStyle(.secondary).monospacedDigit().frame(width: 75, alignment: .leading)
                            Text(message.message).frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.caption)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sourceAndWeather }
                VStack(alignment: .leading, spacing: 8) { sourceAndWeather }
            }.font(.caption)
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
    }

    private var filters: some View {
        HStack(spacing: 14) {
            Picker("Team", selection: Binding(get: { filter.team }, set: { team in
                filter.team = team; filter.reconcile(with: snapshot.drivers)
            })) {
                Text("All teams").tag(String?.none)
                ForEach(LiveTimingFilter.teams(in: snapshot.drivers), id: \.self) { team in
                    Text(team.isEmpty ? "Unknown team" : team).tag(Optional(team))
                }
            }.frame(maxWidth: 260)
            Picker("Driver", selection: $filter.driverID) {
                Text("All drivers").tag(String?.none)
                ForEach(snapshot.drivers.filter { filter.team == nil || $0.team == filter.team }) { driver in
                    Text(driver.name).tag(Optional(driver.id))
                }
            }.frame(maxWidth: 280)
            Text("\(drivers.count) of \(snapshot.drivers.count)").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Clear filters") { filter = LiveTimingFilter() }
                .disabled(filter == LiveTimingFilter())
        }.pickerStyle(.menu)
    }

    @ViewBuilder private var sourceAndWeather: some View {
        Text("Experimental · Direct F1 timing · Provisional data").foregroundStyle(.secondary)
        if let air = snapshot.airTemperature { Text("Air \(air)°C") }
        if let track = snapshot.trackTemperature { Text("Track \(track)°C") }
        Link("Official live timing", destination: URL(string: "https://www.formula1.com/en/timing/f1-live")!)
    }

    private func driverDetail(_ driver: LiveDriverTiming) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(driver.name).fontWeight(.semibold)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), alignment: .leading)], alignment: .leading, spacing: 10) {
                Text("Ahead \(driver.interval ?? "—")")
                Text("Best \(driver.bestLap ?? "—")")
                ForEach(Array(driver.sectors.enumerated()), id: \.offset) { index, time in
                    Text("Sector \(index + 1)  \(time)")
                }
            }.font(.caption).monospacedDigit()
            Text("Tyre history").font(.caption).foregroundStyle(.secondary)
            TyreHistorySummary(segments: driver.tyreHistory, driverName: driver.name, stints: driver.stints)
            Text("Tyre-history lap counts show laps driven on each set. Pit counts are reported by the feed.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
