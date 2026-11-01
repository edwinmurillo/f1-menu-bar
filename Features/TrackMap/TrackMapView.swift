import Combine
import F1Core
import SwiftUI

struct TrackMapView: View {
    let season: SeasonStore
    let liveStore: LiveTimingStore
    let repository: TrackMapRepository
    @State private var weekendID: Int?
    @State private var sessionID: Int?
    @State private var replay: TrackMapReplay?
    @State private var issue: String?
    @State private var isLoading = false
    @State private var isPlaying = true
    @State private var playhead = 0.0
    @State private var selectedDriver: Int?
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var weekends: [RaceWeekend] {
        season.visibleSnapshot.weekends.filter { !$0.isCancelled && !$0.isMissingFromSchedule && $0.firstStart.map { $0 <= season.now } == true }
    }
    private var weekend: RaceWeekend? {
        weekends.first { $0.id == weekendID } ?? weekends.last
    }
    private var sessions: [RaceSession] {
        (weekend?.activeSessions ?? []).filter { $0.start.map { $0 <= season.now } == true }
            .sorted { ($0.start ?? .distantPast, $0.id) < ($1.start ?? .distantPast, $1.id) }
    }
    private var session: RaceSession? { sessions.first { $0.id == sessionID } ?? sessions.last }
    private var preview: TrackMapReplay {
        let live = liveStore.state.snapshot.drivers.compactMap { driver -> (number: Int, name: String, color: String?)? in
            guard let number = Int(driver.id) else { return nil }
            return (number, driver.name, driver.teamColor)
        }
        let standings = season.visibleSnapshot.drivers.compactMap { driver -> (number: Int, name: String, color: String?)? in
            guard let number = driver.driverNumber else { return nil }
            return (number, driver.name, driver.teamColor)
        }
        return .preview(drivers: live.isEmpty ? standings : live, outline: TrackLayoutCatalog.outline(for: weekend))
    }
    private var shown: TrackMapReplay { replay ?? preview }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "Track map", subtitle: "Replay car locations from a sampled session lap")
                    controls
                    if let issue { IssueBanner(message: issue) }
                    if shown.cars.isEmpty {
                        ContentUnavailableView("Track map unavailable", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                               description: Text("A circuit layout and driver roster are needed to show the preview. Try another Grand Prix or refresh the calendar."))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            mapPanel.frame(maxWidth: .infinity)
                            driverList.frame(width: 182)
                        }
                        playbackControls
                    }
                    Text(shown.isPreview
                         ? "Real circuit outline · Car positions are illustrative until OpenF1 location samples load."
                         : "OpenF1 location samples · Approximate car positions for lap \(shown.lap). The outline is traced from one driver's recorded path; lateral placement is not precise.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("About OpenF1 location data", destination: URL(string: "https://openf1.org/docs/#location")!)
                        .font(.caption)
                }
                .padding(26)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: session?.id) { await load() }
        .onReceive(ticker) { _ in
            guard isPlaying, shown.duration > 0 else { return }
            playhead += 0.1 * (shown.isPreview ? 1 : 8)
            if playhead > shown.duration { playhead = 0 }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Grand Prix", selection: Binding(get: { weekend?.id ?? 0 }, set: { weekendID = $0; sessionID = nil })) {
                ForEach(weekends) { weekend in Text(weekend.name).tag(weekend.id) }
            }.frame(maxWidth: 360)
            Picker("Session", selection: Binding(get: { session?.id ?? 0 }, set: { sessionID = $0 })) {
                ForEach(sessions) { session in Text(session.name).tag(session.id) }
            }.frame(maxWidth: 240)
            if isLoading { ProgressView().controlSize(.small) }
            Button { Task { await load() } } label: { Label("Retry", systemImage: "arrow.clockwise") }
                .disabled(session == nil || isLoading)
        }
    }

    private var mapPanel: some View {
        TrackMapCanvas(replay: shown, seconds: playhead, selectedDriver: selectedDriver)
            .frame(minHeight: 390)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Circle().fill(shown.isPreview ? .orange : .green).frame(width: 7, height: 7)
                    Text(shown.isPreview ? "REAL LAYOUT · SIMULATED CARS" : "OPENF1 · LAP \(shown.lap)")
                        .font(.caption2.weight(.bold)).tracking(0.8)
                }
                .padding(10).background(.regularMaterial, in: Capsule()).padding(14)
            }
            .accessibilityLabel(shown.isPreview ? "Real circuit outline with simulated car positions" : "Track map from OpenF1 location samples")
    }

    private var driverList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DRIVERS").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(shown.cars) { car in
                        Button {
                            selectedDriver = selectedDriver == car.id ? nil : car.id
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(Presentation.color(hex: car.teamColor)).frame(width: 8, height: 8)
                                Text(car.abbreviation).font(.caption.weight(.semibold)).frame(width: 35, alignment: .leading)
                                Text(car.name.split(separator: " ").last.map(String.init) ?? car.name)
                                    .font(.caption).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 6)
                            .background(selectedDriver == car.id ? Presentation.accent.opacity(0.14) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Highlight \(car.name)")
                    }
                }
            }
        }
        .padding(12)
        .frame(height: 390)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var playbackControls: some View {
        HStack(spacing: 14) {
            Button { isPlaying.toggle() } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }.buttonStyle(.bordered)
            Slider(value: $playhead, in: 0...max(shown.duration, 1)) { Text("Replay position") }
            Text("\(Int(playhead)) / \(Int(shown.duration)) s")
                .font(.caption.monospacedDigit()).frame(width: 76, alignment: .trailing)
        }
    }

    private func load() async {
        guard let session, season.visibleSnapshot.provider == .openF1 else {
            replay = nil
            issue = "OpenF1 session identifiers are unavailable in this calendar. Showing an illustrative preview."
            return
        }
        isLoading = true; issue = nil
        defer { isLoading = false }
        do {
            replay = try await repository.load(sessionID: session.id)
            playhead = 0; selectedDriver = nil; isPlaying = true
        } catch is CancellationError { }
        catch {
            replay = nil
            issue = "Location data could not be loaded: \(error.localizedDescription) Showing an illustrative preview."
            playhead = 0
        }
    }
}

private struct TrackMapCanvas: View {
    let replay: TrackMapReplay
    let seconds: Double
    let selectedDriver: Int?

    var body: some View {
        Canvas { context, size in
            guard replay.outline.count > 2 else { return }
            let xs = replay.outline.map(\.x), ys = replay.outline.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            let scale = min((size.width - 85) / max(maxX - minX, 1), (size.height - 85) / max(maxY - minY, 1))
            let offsetX = (size.width - (maxX - minX) * scale) / 2
            let offsetY = (size.height - (maxY - minY) * scale) / 2
            func point(_ value: TrackMapPoint) -> CGPoint {
                CGPoint(x: offsetX + (value.x - minX) * scale,
                        y: size.height - offsetY - (value.y - minY) * scale)
            }
            var path = Path()
            path.move(to: point(replay.outline[0]))
            for coordinate in replay.outline.dropFirst() { path.addLine(to: point(coordinate)) }
            if replay.isPreview { path.closeSubpath() }
            context.stroke(path, with: .color(.primary.opacity(0.11)), style: StrokeStyle(lineWidth: 19, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            for car in replay.cars {
                guard let location = car.position(at: seconds) else { continue }
                let center = point(location)
                let selected = car.id == selectedDriver
                let color = Presentation.color(hex: car.teamColor)
                let radius: CGFloat = selected ? 15 : 11
                let marker = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
                context.fill(marker, with: .color(color))
                context.stroke(marker, with: .color(.white), lineWidth: selected ? 2.5 : 1.5)
                let label = Text(String(car.id)).font(.system(size: selected ? 10 : 8, weight: .bold))
                    .foregroundColor(.white)
                context.draw(label, at: center)
                if selected {
                    let name = Text(car.name).font(.caption.weight(.bold)).foregroundColor(.primary)
                    context.draw(name, at: CGPoint(x: center.x, y: center.y - 25), anchor: .bottom)
                }
            }
        }
    }
}
