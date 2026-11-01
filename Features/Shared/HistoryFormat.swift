import F1Core
import Foundation

enum HistoryFormat {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds <= 86_400 else { return "—" }
        let milliseconds = Int((seconds * 1_000).rounded())
        return String(format: "%d:%02d.%03d", milliseconds / 60_000, (milliseconds / 1000) % 60, milliseconds % 1000)
    }
    static func gap(_ value: RaceHistoryGap?) -> String {
        switch value {
        case .seconds(let seconds): seconds == 0 ? "Leader" : String(format: "+%.3f", seconds)
        case .laps(let count): "+\(count) lap\(count == 1 ? "" : "s")"
        case nil: "—"
        }
    }
}
