import Combine
import F1Core
import SwiftUI

struct LiveTimingTrackMiniature: View {
    let snapshot: LiveTimingSnapshot
    let weekend: RaceWeekend
    let lap: Int
    @State private var elapsed = 0.0
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var outline: [TrackMapPoint] { TrackLayoutCatalog.outline(for: weekend) }
    private var estimate: TrackTimingEstimate? {
        TrackTimingEstimate.make(snapshot: snapshot, playbackSeconds: elapsed, lap: lap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("LAP \(lap) · 2× SIMULATION")
                    .font(.system(size: 10, weight: .bold)).tracking(0.6)
                Spacer(minLength: 0)
                if let estimate {
                    Text("\(Int(elapsed)) / \(Int(estimate.leaderLapTime / 2))s")
                        .font(.system(size: 10).monospacedDigit())
                }
            }.foregroundStyle(.secondary)
            Canvas { context, size in
                guard let estimate, outline.count > 2 else { return }
                let xs = outline.map(\.x), ys = outline.map(\.y)
                guard let minX = xs.min(), let maxX = xs.max(),
                      let minY = ys.min(), let maxY = ys.max() else { return }
                let width = max(maxX - minX, 1), height = max(maxY - minY, 1)
                let scale = min((size.width - 20) / width, (size.height - 20) / height)
                let left = (size.width - width * scale) / 2
                let top = (size.height - height * scale) / 2
                func screen(_ point: TrackMapPoint) -> CGPoint {
                    CGPoint(x: left + (point.x - minX) * scale,
                            y: size.height - top - (point.y - minY) * scale)
                }
                var path = Path()
                for (index, point) in outline.enumerated() {
                    if index == 0 { path.move(to: screen(point)) }
                    else { path.addLine(to: screen(point)) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.primary.opacity(0.65)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                let start = screen(outline[0]), next = screen(outline[1])
                let dx = next.x - start.x, dy = next.y - start.y
                let length = max(hypot(dx, dy), 0.001)
                var line = Path()
                line.move(to: CGPoint(x: start.x + dy / length * 6, y: start.y - dx / length * 6))
                line.addLine(to: CGPoint(x: start.x - dy / length * 6, y: start.y + dx / length * 6))
                context.stroke(line, with: .color(.orange), lineWidth: 3)
                let replay = TrackMapReplay.preview(drivers: [], outline: outline)
                for driver in snapshot.drivers {
                    guard let number = Int(driver.id),
                          let fraction = estimate.progressByNumber[number],
                          let location = replay.positionOnOutline(at: fraction) else { continue }
                    let center = screen(location), radius: CGFloat = number == estimate.leaderNumber ? 6 : 4
                    let marker = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2))
                    context.fill(marker, with: .color(number == estimate.leaderNumber ? .orange :
                        Presentation.color(hex: driver.teamColor)))
                    context.stroke(marker, with: .color(.white), lineWidth: 1)
                }
            }
            .frame(height: 104)
        }
        .padding(9)
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Lap \(lap) track simulation at twice speed based on leader lap time and driver gaps")
        .onReceive(ticker) { _ in
            guard let estimate else { return }
            elapsed += 0.1
            if elapsed >= estimate.leaderLapTime / 2 { elapsed = 0 }
        }
    }
}
