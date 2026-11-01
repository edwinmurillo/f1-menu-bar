import F1Core
import SwiftUI

struct CircuitThumbnail: View {
    let weekend: RaceWeekend

    var body: some View {
        let outline = TrackLayoutCatalog.outline(for: weekend)
        Canvas { context, size in
            guard outline.count > 2 else { return }
            let xs = outline.map(\.x), ys = outline.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let width = max(maxX - minX, 1), height = max(maxY - minY, 1)
            let inset: CGFloat = 4
            let scale = min((size.width - inset * 2) / width, (size.height - inset * 2) / height)
            let left = (size.width - width * scale) / 2
            let top = (size.height - height * scale) / 2
            var path = Path()
            for (index, point) in outline.enumerated() {
                let coordinate = CGPoint(x: left + (point.x - minX) * scale,
                                         y: size.height - top - (point.y - minY) * scale)
                if index == 0 { path.move(to: coordinate) }
                else { path.addLine(to: coordinate) }
            }
            path.closeSubpath()
            context.stroke(path, with: .color(.primary.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
