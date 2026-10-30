import F1Core
import SwiftUI

enum Presentation {
    static func providerName(_ provider: DataProvider) -> String {
        provider == .openF1 ? "OpenF1" : "Jolpica · backup"
    }
    static func providerURL(_ provider: DataProvider) -> URL {
        URL(string: provider == .openF1 ? "https://openf1.org/" : "https://github.com/jolpica/jolpica-f1")!
    }
    static let accent = Color(red: 0.87, green: 0.25, blue: 0.20)
    static func date(_ date: Date?, format: String, zone: TimeZone) -> String {
        guard let date else { return "Time TBC" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter.string(from: date)
    }
    static func countdown(until date: Date, now: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
    static func session(_ name: String) -> String {
        name == "Race" ? "Grand Prix" : name == "Sprint Shootout" ? "Sprint Qualifying" : name
    }
    static func shortSession(_ name: String) -> String {
        switch name {
        case "Practice 1": "P1"
        case "Practice 2": "P2"
        case "Practice 3": "P3"
        case "Qualifying": "Q"
        case "Sprint Qualifying", "Sprint Shootout": "SQ"
        case "Sprint": "Sprint"
        case "Race": "GP"
        default: name
        }
    }
    static func status(_ status: WeekendStatus) -> String {
        switch status {
        case .raced: "Raced"
        case .current: "Current weekend"
        case .next: "Next"
        case .future: "Future"
        case .resultsPending: "Results pending"
        case .cancelled: "Cancelled"
        case .unavailable: "Schedule changed"
        }
    }
    static func statusColor(_ status: WeekendStatus) -> Color {
        switch status {
        case .raced: .green
        case .current, .next: accent
        default: .secondary
        }
    }
    static func color(hex: String?) -> Color {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return .secondary }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static func weekendDates(_ weekend: RaceWeekend, zone: TimeZone) -> String {
        let start = date(weekend.firstStart, format: "d MMM", zone: zone)
        let end = date(weekend.grandPrix?.start, format: "d MMM yyyy", zone: zone)
        return "\(start) – \(end)"
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 25, weight: .semibold)).tracking(-0.6)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusBadge: View {
    let status: WeekendStatus
    var body: some View {
        Text(Presentation.status(status)).font(.caption).fontWeight(status == .next ? .semibold : .regular)
            .foregroundStyle(Presentation.statusColor(status))
    }
}

struct TyreLabel: View {
    let compound: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                .accessibilityHidden(true)
            Text(compound?.capitalized ?? "Unknown").font(.caption)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch compound {
        case "SOFT": .red
        case "MEDIUM": .yellow
        case "HARD": .white
        case "INTERMEDIATE": .green
        case "WET": .blue
        default: .gray
        }
    }
}

struct IssueBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(message)
    }
}

struct SessionScheduleView: View {
    let weekend: RaceWeekend
    let now: Date
    let zone: TimeZone
    var compact = false

    private var days: [(String, [RaceSession])] {
        var groups: [(String, [RaceSession])] = []
        for session in weekend.sessions {
            let key = Presentation.date(session.start, format: "EEEE d MMM", zone: zone)
            if groups.last?.0 == key { groups[groups.count - 1].1.append(session) }
            else { groups.append((key, [session])) }
        }
        return groups
    }
    var body: some View {
        let nextID = SchedulePolicy().nextSession(in: weekend, now: now)?.id
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 8) {
                    Text(day.0.uppercased()).font(.system(size: 11, weight: .semibold))
                        .tracking(0.8).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(day.1) { session in
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(session.id == nextID ? Presentation.accent : session.isGrandPrix ? Color.primary : Color.secondary.opacity(0.35))
                                .frame(width: 4, height: session.isGrandPrix ? 13 : 4)
                                .accessibilityHidden(true)
                            Text(Presentation.session(session.name))
                                .fontWeight(session.isGrandPrix ? .semibold : .regular)
                            Spacer(minLength: 8)
                            Text(session.isCancelled ? "Cancelled" : Presentation.date(session.start, format: "jmm", zone: zone))
                                .monospacedDigit().fontWeight(.medium)
                        }
                        .font(.system(size: compact ? 12 : 13))
                        .foregroundStyle(session.isCancelled ? .secondary : .primary)
                        .padding(.vertical, compact ? 2 : 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}
