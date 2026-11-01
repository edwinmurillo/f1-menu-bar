import F1Core
import SwiftUI

struct SeasonWinsView: View {
    let victories: [WeekendVictory]
    let drivers: Bool
    let qualifyingAvailable: Bool
    let racesAvailable: Bool
    var driverName = ""
    var showAll: (() -> Void)?

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
            } else if drivers {
                AdaptiveInlinePreview(count: victories.count) { visible, compact in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            ForEach(SeasonWinPresentation.newestFirst(victories).prefix(visible)) { victory in
                                Button { showAll?() } label: {
                                    HStack(spacing: 4) {
                                        Text(SeasonWinPresentation.kind(victory)).fixedSize()
                                        Text(SeasonWinPresentation.event(victory)).lineLimit(1).truncationMode(.middle)
                                        Text(SeasonWinPresentation.flag(country: victory.weekend.country)).fixedSize()
                                    }.font(.caption)
                                        .padding(.horizontal, 7).padding(.vertical, 5)
                                        .frame(maxWidth: compact ? .infinity : nil)
                                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .help(SeasonWinPresentation.label(victory) + " · " + victory.weekend.country + " · Click for details")
                                    .accessibilityLabel(SeasonWinPresentation.label(victory) + ", " + victory.weekend.country + ", show details")
                            }
                        }
                        if visible < victories.count {
                            HStack(spacing: 10) {
                                Text("Latest \(visible) of \(victories.count) weekends").foregroundStyle(.secondary)
                                if let showAll {
                                    Button("Show more", action: showAll)
                                        .accessibilityLabel("Show all season wins and details for \(driverName)")
                                }
                            }.font(.caption).padding(.top, 3)
                        }
                    }
                }
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
    static func newestFirst(_ victories: [WeekendVictory]) -> [WeekendVictory] {
        victories.sorted {
            // Undated results remain visible, but do not displace known recent wins.
            ($0.weekend.grandPrix?.start ?? $0.weekend.firstStart ?? .distantPast, $0.id) >
            ($1.weekend.grandPrix?.start ?? $1.weekend.firstStart ?? .distantPast, $1.id)
        }
    }

    static func recent(_ victories: [WeekendVictory]) -> [WeekendVictory] {
        Array(newestFirst(victories).prefix(3))
    }

    static func label(_ victory: WeekendVictory) -> String {
        "\(kind(victory)) – \(event(victory))"
    }

    static func kind(_ victory: WeekendVictory) -> String {
        victory.qualifying && victory.grandPrix ? "Quali & GP" : victory.qualifying ? "Quali" : "GP"
    }

    static func event(_ victory: WeekendVictory) -> String {
        victory.weekend.name.replacingOccurrences(of: " Grand Prix", with: "", options: .caseInsensitive)
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
