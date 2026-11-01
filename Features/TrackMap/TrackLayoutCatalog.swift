import F1Core
import Foundation

enum TrackLayoutCatalog {
    private struct Layout: Decodable {
        let name: String
        let location: String
        let points: [[Double]]
    }

    private static let layouts: [Layout] = {
        guard let url = Bundle.main.url(forResource: "TrackLayouts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layouts = try? JSONDecoder().decode([Layout].self, from: data) else { return [] }
        return layouts
    }()

    static func outline(for weekend: RaceWeekend?) -> [TrackMapPoint] {
        guard let weekend else { return [] }
        let location = normalized(weekend.location)
        let circuit = normalized(weekend.circuit)
        let name = normalized(weekend.name)
        let match = layouts.first { normalized($0.name) == circuit }
            ?? layouts.first { !location.isEmpty && normalized($0.location) == location }
            ?? layouts.first { !location.isEmpty && (normalized($0.location).contains(location) || location.contains(normalized($0.location))) }
            ?? layouts.first { name.contains(normalized($0.location)) }
        return match?.points.compactMap { point in
            guard point.count == 2, point[0].isFinite, point[1].isFinite else { return nil }
            return TrackMapPoint(x: point[0], y: point[1])
        } ?? []
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
