import F1Core
import SwiftUI

struct LiveTimingView: View {
    let store: LiveTimingStore
    let preferences: AppPreferences
    @State private var selectedDriver: String?
    private var snapshot: LiveTimingSnapshot { store.state.snapshot }
    private var selected: LiveDriverTiming? {
        snapshot.drivers.first { $0.id == selectedDriver } ?? snapshot.drivers.first
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content(tableHeight: max(230, viewport.size.height / 2), minimumHeight: viewport.size.height)
            }
        }
        .onChange(of: snapshot.sessionID) { _, _ in selectedDriver = nil }
    }

    private func content(tableHeight: CGFloat, minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Live timing", subtitle: "Experimental personal connection")
            LiveTimingConnectionHeader(store: store, preferences: preferences)
            if snapshot.drivers.isEmpty {
                Spacer(minLength: 24)
                LiveTimingPlaceholder(phase: store.state.phase, isRunning: store.isRunning)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
            } else {
                Table(snapshot.drivers, selection: $selectedDriver) {
                    TableColumn("Pos") { driver in
                        Text(driver.position.map(String.init) ?? "—").monospacedDigit()
                    }.width(32)
                    TableColumn("Driver") { driver in
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2).fill(Presentation.color(hex: driver.teamColor)).frame(width: 3, height: 26).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(driver.name).fontWeight(.medium).lineLimit(1)
                                Text(driver.retired ? "Retired" : driver.inPit ? "In pit lane" : driver.pitOut == true ? "Out lap" : driver.knockedOut ? "Knocked out" : driver.team)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.padding(.vertical, 4)
                    }.width(min: 140, ideal: 210)
                    TableColumn("Gap") { driver in Text(driver.gap ?? "—").monospacedDigit() }.width(74)
                    TableColumn("Last lap") { driver in Text(driver.lastLap ?? "—").monospacedDigit() }.width(86)
                    TableColumn("Tyre / age") { driver in
                        VStack(alignment: .leading, spacing: 3) {
                            TyreLabel(compound: driver.currentTyre?.compound)
                            Text(driver.currentTyre?.tyreAge.map { "\($0) laps" } ?? "Age unknown").font(.caption).foregroundStyle(.secondary)
                        }
                    }.width(100)
                    TableColumn("Laps") { driver in Text(driver.laps.map(String.init) ?? "—").monospacedDigit() }.width(36)
                    TableColumn("Stops") { driver in Text(driver.stops.map(String.init) ?? "—").monospacedDigit() }.width(36)
                    TableColumn("Pit") { driver in
                        Text(driver.inPit ? "PIT" : driver.pitOut == true ? "OUT" : "—")
                            .foregroundStyle(driver.inPit ? Color.orange : driver.pitOut == true ? Color.green : Color.secondary)
                    }.width(36)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: false))
                // A native Table's unconstrained fitting height can enlarge the entire
                // NavigationSplitView, moving both columns outside the window's bounds.
                .frame(height: tableHeight)
                if let driver = selected { driverDetail(driver) }
            }
            if !snapshot.messages.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("RACE CONTROL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(snapshot.messages) { message in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(message.date.map { Presentation.date($0, format: "jmmss", zone: preferences.timeZone) } ?? "—")
                                        .foregroundStyle(.secondary).monospacedDigit().frame(width: 75, alignment: .leading)
                                    Text(message.message).frame(maxWidth: .infinity, alignment: .leading)
                                }.font(.caption)
                            }
                        }
                    }.frame(height: 78)
                }
            }
            HStack(spacing: 12) {
                Text("Experimental · Direct F1 timing · Provisional data").foregroundStyle(.secondary)
                Spacer()
                if let air = snapshot.airTemperature { Text("Air \(air)°C") }
                if let track = snapshot.trackTemperature { Text("Track \(track)°C") }
                Link("Official live timing", destination: URL(string: "https://www.formula1.com/en/timing/f1-live")!)
            }.font(.caption)
        }
        .padding(26)
        // Give the empty state's spacers a real viewport to center within. Keep
        // the ScrollView so long connection messages can still be reached.
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
    }

    private func driverDetail(_ driver: LiveDriverTiming) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 15) {
                Text(driver.name).fontWeight(.semibold)
                Text("Ahead \(driver.interval ?? "—")")
                Text("Best \(driver.bestLap ?? "—")")
                Spacer()
                Text(driver.sectors.enumerated().map { "S\($0.offset + 1) \($0.element)" }.joined(separator: "   "))
                    .foregroundStyle(.secondary)
            }.font(.caption).monospacedDigit()
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    Text("Tyre history").font(.caption).foregroundStyle(.secondary)
                    if driver.stints.isEmpty { Text("Waiting for tyre data").font(.caption).foregroundStyle(.secondary) }
                    ForEach(driver.stints) { stint in
                        HStack(spacing: 6) {
                            TyreLabel(compound: stint.compound)
                            if let age = stint.tyreAge { Text("\(age) laps").font(.caption).monospacedDigit() }
                            if stint.isNew == false { Text("Used").font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            Text("Tyre age includes laps completed before fitting used tyres. Pit counts are reported by the feed; exact stop durations and future strategy are unavailable here.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

}
