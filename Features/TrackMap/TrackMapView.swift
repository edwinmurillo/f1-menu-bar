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
    @State private var clockNow = Date()
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var weekends: [RaceWeekend] {
        season.visibleSnapshot.weekends.filter { !$0.isCancelled && !$0.isMissingFromSchedule && $0.firstStart.map { $0 <= season.now } == true }
    }
    private var weekend: RaceWeekend? {
        if let selected = weekends.first(where: { $0.id == weekendID }) { return selected }
        if liveStore.state.phase == .connected,
           liveStore.state.snapshot.hasFreshTiming(at: clockNow),
           let meeting = liveStore.state.snapshot.meetingName?.lowercased(),
           let current = weekends.first(where: {
               $0.name.lowercased().contains(meeting) || meeting.contains($0.name.lowercased())
           }) { return current }
        return weekends.last(where: { $0.winner != nil }) ?? weekends.last
    }
    private var sessions: [RaceSession] {
        (weekend?.activeSessions ?? []).filter { $0.start.map { $0 <= season.now } == true }
            .sorted { ($0.start ?? .distantPast, $0.id) < ($1.start ?? .distantPast, $1.id) }
    }
    private var session: RaceSession? { sessions.first { $0.id == sessionID } ?? sessions.last }
    private var matchesLiveSession: Bool {
        guard let weekend, let session, let meeting = liveStore.state.snapshot.meetingName,
              let name = liveStore.state.snapshot.sessionName else { return false }
        let selected = weekend.name.lowercased(), reported = meeting.lowercased()
        return (selected.contains(reported) || reported.contains(selected)) &&
            name.caseInsensitiveCompare(session.name) == .orderedSame
    }
    private var timingEstimate: TrackTimingEstimate? {
        guard shown.isPreview, matchesLiveSession, liveStore.state.phase == .connected else { return nil }
        return TrackTimingEstimate.make(snapshot: liveStore.state.snapshot,
            playbackSeconds: playhead, now: clockNow)
    }
    private var preview: TrackMapReplay {
        let live = liveStore.state.snapshot.drivers.compactMap { driver -> (number: Int, name: String, color: String?)? in
            guard let number = Int(driver.id) else { return nil }
            return (number, driver.name, driver.teamColor)
        }
        let standings = season.visibleSnapshot.drivers.compactMap { driver -> (number: Int, name: String, color: String?)? in
            guard let number = driver.driverNumber else { return nil }
            return (number, driver.name, driver.teamColor)
        }
        return .preview(drivers: matchesLiveSession && !live.isEmpty ? live : standings,
                        outline: TrackLayoutCatalog.outline(for: weekend))
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
                    Text(timingEstimate != nil
                         ? "2× timing simulation · The leader completes the last lap in half its reported time. Other cars are offset by their gap as a share of that lap. These are not measured coordinates."
                         : shown.isPreview
                         ? "Real circuit outline · Car positions are illustrative until recorded location samples load. Start/finish is approximate on uncalibrated layouts."
                         : "\(shown.sourceName) · Recorded car positions for lap \(shown.lap). The outline and cars use the same X/Y coordinates; lateral placement is approximate.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link(shown.sourceName.hasPrefix("TracingInsights") ? "Recorded telemetry source" : "About OpenF1 location data",
                         destination: URL(string: shown.sourceName.hasPrefix("TracingInsights")
                             ? "https://github.com/TracingInsights/\(weekend?.year ?? season.visibleSnapshot.year)"
                             : "https://openf1.org/docs/#location")!)
                        .font(.caption)
                }
                .padding(26)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: session?.id) { await load() }
        .onReceive(ticker) { _ in
            clockNow = Date()
            guard isPlaying else { return }
            if let estimate = timingEstimate {
                playhead += 0.1
                if playhead >= estimate.leaderLapTime / 2 { playhead = 0 }
            } else if shown.duration > 0 {
                playhead += 0.1 * (shown.isPreview ? 1 : 8)
                if playhead > shown.duration { playhead = 0 }
            }
        }
        .onChange(of: liveStore.state.snapshot.drivers.first(where: { $0.position == 1 })?.lastLap) { _, _ in
            if shown.isPreview { playhead = 0 }
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
        TrackMapCanvas(replay: shown, seconds: playhead, selectedDriver: selectedDriver, estimate: timingEstimate)
            .frame(minHeight: 390)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Circle().fill(shown.isPreview ? .orange : .green).frame(width: 7, height: 7)
                    Text(timingEstimate.map { "TIMING ESTIMATE · LAP \($0.lap)" } ??
                         (shown.isPreview ? "REAL LAYOUT · SIMULATED CARS" : "RECORDED POSITION · LAP \(shown.lap)"))
                        .font(.caption2.weight(.bold)).tracking(0.8)
                }
                .padding(10).background(.regularMaterial, in: Capsule()).padding(14)
            }
            .accessibilityLabel(timingEstimate != nil ? "Real circuit outline with car positions estimated from live timing" :
                shown.isPreview ? "Real circuit outline with simulated car positions" : "Track map from recorded car locations")
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
        Group {
            if let estimate = timingEstimate {
                HStack(spacing: 14) {
                    Button { isPlaying.toggle() } label: {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    }.buttonStyle(.bordered)
                    Slider(value: $playhead, in: 0...estimate.leaderLapTime / 2) { Text("Simulated lap position") }
                    Text("2× · \(Int(playhead)) / \(Int(estimate.leaderLapTime / 2)) s")
                        .font(.caption.monospacedDigit()).frame(width: 100, alignment: .trailing)
                }
            } else {
                HStack(spacing: 14) {
                    Button { isPlaying.toggle() } label: {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    }.buttonStyle(.bordered)
                    Slider(value: $playhead, in: 0...max(shown.duration, 1)) { Text("Replay position") }
                    Text("\(Int(playhead)) / \(Int(shown.duration)) s")
                        .font(.caption.monospacedDigit()).frame(width: 76, alignment: .trailing)
                }
            }
        }
    }

    private func load() async {
        guard let session, let weekend else {
            replay = nil
            issue = "No started session is available. Showing an illustrative preview."
            return
        }
        isLoading = true; issue = nil
        defer { isLoading = false }
        do {
            replay = try await repository.load(sessionID: session.id, weekend: weekend, session: session,
                                               preferOpenF1: season.visibleSnapshot.provider == .openF1)
            playhead = 0; selectedDriver = nil; isPlaying = true
        } catch is CancellationError { }
        catch {
            replay = nil
            issue = "Recorded car locations could not be loaded: \(error.localizedDescription) Showing an illustrative preview."
            playhead = 0
        }
    }
}

private struct TrackMapCanvas: View {
    let replay: TrackMapReplay
    let seconds: Double
    let selectedDriver: Int?
    let estimate: TrackTimingEstimate?

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
            let start = point(replay.outline[0])
            let nextCoordinate = replay.outline.dropFirst().first {
                hypot($0.x - replay.outline[0].x, $0.y - replay.outline[0].y) > 1
            } ?? replay.outline[1]
            let next = point(nextCoordinate)
            let dx = next.x - start.x, dy = next.y - start.y
            let tangentLength = max(hypot(dx, dy), 0.001)
            let crossX = -dy / tangentLength * 13, crossY = dx / tangentLength * 13
            var startLine = Path()
            startLine.move(to: CGPoint(x: start.x - crossX, y: start.y - crossY))
            startLine.addLine(to: CGPoint(x: start.x + crossX, y: start.y + crossY))
            context.stroke(startLine, with: .color(.black), style: StrokeStyle(lineWidth: 8, lineCap: .butt))
            context.stroke(startLine, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .butt))
            context.draw(Text(replay.isPreview ? "START / FINISH ≈" : "START / FINISH")
                .font(.caption2.weight(.bold)).foregroundColor(.primary),
                at: CGPoint(x: start.x, y: start.y - 20), anchor: .bottom)
            for car in replay.cars {
                let location: TrackMapPoint?
                if let estimate {
                    location = estimate.progressByNumber[car.id].flatMap { replay.positionOnOutline(at: $0) }
                } else { location = car.position(at: seconds) }
                guard let location else { continue }
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
