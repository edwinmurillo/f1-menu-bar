import F1Core
import SwiftUI

struct SeasonWinsView: View {
    let victories: [WeekendVictory]
    let drivers: Bool
    let qualifyingAvailable: Bool
    let racesAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if drivers {
                Text("\(qualifyingAvailable ? String(victories.filter(\.qualifying).count) : "—") Quali · \(raceCount) GP")
                    .font(.caption.weight(.medium)).monospacedDigit()
            } else {
                Text("\(raceCount) GP").font(.caption.weight(.medium)).monospacedDigit()
            }
            if victories.isEmpty {
                Text(racesAvailable && (!drivers || qualifyingAvailable) ? "No wins yet" : "Results pending")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: drivers ? 8 : 6) {
                        ForEach(victories) { victory in
                            HStack(spacing: 5) {
                                Text(SeasonWinPresentation.flag(country: victory.weekend.country))
                                if drivers { Text(SeasonWinPresentation.label(victory)).font(.caption) }
                            }
                            .padding(.horizontal, drivers ? 7 : 2).padding(.vertical, 4)
                            .background(.quaternary.opacity(drivers ? 0.35 : 0), in: RoundedRectangle(cornerRadius: 5))
                            .help(SeasonWinPresentation.label(victory) + " · " + victory.weekend.country)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(SeasonWinPresentation.label(victory) + ", " + victory.weekend.country)
                        }
                    }
                }.frame(height: 32)
            }
        }.padding(.vertical, 5)
    }

    private var raceCount: String { racesAvailable ? String(victories.filter(\.grandPrix).count) : "—" }
}

enum SeasonWinPresentation {
    static func label(_ victory: WeekendVictory) -> String {
        let kind = victory.qualifying && victory.grandPrix ? "Quali & GP" : victory.qualifying ? "Quali" : "GP"
        let event = victory.weekend.name.replacingOccurrences(of: " Grand Prix", with: "", options: .caseInsensitive)
        return "\(kind) – \(event)"
    }

    static func flag(country: String) -> String {
        let key = country.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code = regions[key] ?? aliases[key] else { return "🌐" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }

    private static let aliases = ["uk": "GB", "great britain": "GB", "usa": "US", "uae": "AE", "korea": "KR"]
    private static let regions: [String: String] = {
        let locale = Locale(identifier: "en_US")
        var result: [String: String] = [:]
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            guard let name = locale.localizedString(forRegionCode: region.identifier) else { continue }
            result[name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)] = region.identifier
            result[region.identifier.lowercased()] = region.identifier
        }
        return result
    }()
}
