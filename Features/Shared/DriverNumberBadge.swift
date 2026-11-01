import SwiftUI

/// Cosmetic fallback for providers without team colors; never joins provider
/// standings or identities. Palette verified against the 2026-11-01 timing roster.
enum TeamAppearance {
    static func hex(team: String, provided: String?) -> String? {
        if let provided, provided.count == 6, UInt32(provided, radix: 16) != nil { return provided }
        let key = team.lowercased().filter { $0.isLetter || $0.isNumber }
        return palette[key]
    }
    static func color(team: String, provided: String?) -> Color {
        Presentation.color(hex: hex(team: team, provided: provided))
    }
    private static let palette = [
        "alpine": "00A1E8", "alpinef1team": "00A1E8",
        "astonmartin": "229971", "audi": "F50537",
        "cadillac": "909090", "cadillacf1team": "909090",
        "ferrari": "ED1131", "haas": "9C9FA2", "haasf1team": "9C9FA2",
        "mclaren": "F47600", "mercedes": "00D7B6",
        "racingbulls": "6C98FF", "rbf1team": "6C98FF",
        "redbull": "4781D7", "redbullracing": "4781D7", "williams": "1868DB"
    ]
}

struct DriverNumberBadge: View {
    let number: String
    let team: String
    var colorHex: String?
    var body: some View {
        Text(number).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .overlay(Circle().strokeBorder(TeamAppearance.color(team: team, provided: colorHex), lineWidth: 2))
            .accessibilityLabel("Racing number \(number)")
    }
}
