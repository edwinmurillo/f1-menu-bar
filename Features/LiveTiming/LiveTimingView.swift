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
                content(tableHeight: max(230, viewport.size.height / 2))
            }
        }
        .onChange(of: snapshot.sessionID) { _, _ in selectedDriver = nil }
    }

    private func content(tableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionHeader(title: "Live timing", subtitle: [snapshot.meetingName, snapshot.sessionName].compactMap { $0 }.joined(separator: " · "))
                Button(store.isRunning ? "Disconnect" : "Connect") {
                    if store.isRunning { store.disconnect() } else { store.connect() }
                }.buttonStyle(.bordered)
            }
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                HStack(spacing: 12) {
                    Label(status(at: clock.date), systemImage: isLive(at: clock.date) ? "dot.radiowaves.left.and.right" : "clock")
                        .foregroundStyle(isLive(at: clock.date) ? Color.green : Color.secondary)
                    if let current = snapshot.currentLap {
                        Text(snapshot.totalLaps.map { "Lap \(current) / \($0)" } ?? "Lap \(current)").monospacedDigit()
                    }
                    if let track = snapshot.trackStatus { Text(track).foregroundStyle(.secondary) }
                    Spacer()
                    if let date = snapshot.receivedAt {
                        Text("Received \(Presentation.date(date, format: "jmmss", zone: preferences.timeZone))")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }.font(.caption)
            }
            if let message = store.state.message {
                IssueBanner(message: message + (store.state.retryAt.map { " Retry after \(Presentation.date($0, format: "jmmss", zone: preferences.timeZone))." } ?? ""))
            }
            if snapshot.drivers.isEmpty {
                ContentUnavailableView(store.isRunning ? "Waiting for session timing" : "Connect to follow a session",
                    systemImage: "flag.checkered", description: Text("Positions, laps, tyres and pit counts appear when F1 publishes them. This view connects while it is visible."))
                    .frame(height: tableHeight)
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
                                Text(driver.retired ? "Retired" : driver.inPit ? "In pit lane" : driver.knockedOut ? "Knocked out" : driver.team)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.padding(.vertical, 4)
                    }.width(min: 140, ideal: 210)
                    TableColumn("Gap") { driver in Text(driver.gap ?? "—").monospacedDigit() }.width(74)
                    TableColumn("Last lap") { driver in Text(driver.lastLap ?? "—").monospacedDigit() }.width(86)
                    TableColumn("Tyre / age") { driver in
                        VStack(alignment: .leading, spacing: 3) {
                            tyreLabel(driver.currentTyre?.compound)
                            Text(driver.currentTyre?.tyreAge.map { "\($0) laps" } ?? "Age unknown").font(.caption).foregroundStyle(.secondary)
                        }
                    }.width(100)
                    TableColumn("Laps") { driver in Text(driver.laps.map(String.init) ?? "—").monospacedDigit() }.width(36)
                    TableColumn("Stops") { driver in Text(driver.stops.map(String.init) ?? "—").monospacedDigit() }.width(36)
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
    }

    private func isLive(at now: Date) -> Bool { store.state.phase == .connected && snapshot.hasFreshTiming(at: now) }
    private func status(at now: Date) -> String {
        switch store.state.phase {
        case .stopped: return "Disconnected · last received data"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting · timing may be outdated"
        case .unavailable: return "Live timing unavailable"
        case .connected:
            if isLive(at: now) { return "Live" }
            if snapshot.hasFinished { return "Session finished · latest available timing" }
            if snapshot.sessionStatus == "Aborted" { return "Session suspended" }
            return snapshot.lastTimingUpdate == nil ? "Connected · waiting for fresh timing" : "No recent timing · data may be outdated"
        }
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
                            tyreLabel(stint.compound)
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

    private func tyreLabel(_ compound: String?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tyreColor(compound)).frame(width: 8, height: 8)
                .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5)).accessibilityHidden(true)
            Text(compound?.capitalized ?? "Unknown").font(.caption)
        }.accessibilityElement(children: .combine)
    }
    private func tyreColor(_ compound: String?) -> Color {
        switch compound {
        case "SOFT": .red
        case "MEDIUM": .yellow
        case "HARD": .white
        case "INTERMEDIATE": .green
        case "WET": .blue
        default: .gray
        }
    }
}
