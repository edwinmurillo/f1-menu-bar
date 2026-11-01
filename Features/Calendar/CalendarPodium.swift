import F1Core
import SwiftUI

struct CalendarPodium: View {
    let weekend: RaceWeekend
    var compact = false
    private func driver(_ position: Int) -> RaceWinner? {
        weekend.podium?.first { $0.position == position }?.driver ?? (position == 1 ? weekend.winner : nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 10) {
            ForEach(1...3, id: \.self) { position in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(position == 1 ? Color(red: 0.85, green: 0.65, blue: 0.13) : position == 2 ? Color(red: 0.7, green: 0.73, blue: 0.77) : Color(red: 0.72, green: 0.43, blue: 0.23))
                    if let driver = driver(position) {
                        Text(compact ? driver.driverName.split(separator: " ").last.map(String.init) ?? driver.driverName : driver.driverName)
                            .fontWeight(position == 1 ? .semibold : .regular)
                            .lineLimit(compact ? 1 : nil)
                            .help("P\(position) · \(driver.driverName) · \(driver.team)")
                    } else { Text("—").foregroundStyle(.secondary) }
                }.font(compact ? .caption : .callout)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Position \(position), \(driver(position)?.driverName ?? "not published")")
            }
        }
        .frame(maxWidth: compact ? 130 : .infinity, alignment: .leading)
    }
}
