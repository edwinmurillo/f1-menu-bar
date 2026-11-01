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
        case .future: "Upcoming"
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

    private var color: Color { TyreColor.forCompound(compound) }
}

private enum TyreColor {
    static func forCompound(_ compound: String?) -> Color {
        switch compound?.uppercased() {
        case "SOFT": .red
        case "MEDIUM": .yellow
        case "HARD": .white
        case "INTERMEDIATE": .green
        case "WET": .blue
        default: .gray
        }
    }
}

struct TyreHistoryLabel: View {
    let segments: [TyreHistorySegment]?

    var body: some View {
        Group {
            if let segments, !segments.isEmpty {
                TyreHistoryFlow(spacing: 5) {
                    ForEach(segments.indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            TyreHistoryBadge(compound: segments[index].compound)
                            if let laps = segments[index].completedLaps {
                                Text("\(laps) \(laps == 1 ? "Lap" : "Laps")").monospacedDigit()
                            } else if index == segments.count - 1 {
                                Text("Current").foregroundStyle(.secondary)
                            } else {
                                Text("— Laps").foregroundStyle(.secondary)
                            }
                            if index < segments.count - 1 {
                                Text("–").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tyre history: \(segments.map { "\(TyreHistoryBadge.letter($0.compound))" + ($0.completedLaps.map { " \($0) \($0 == 1 ? "lap" : "laps")" } ?? "") }.joined(separator: ", "))")
            } else {
                Text("—").font(.caption2).accessibilityLabel("Tyre history unavailable")
            }
        }
    }
}

private struct TyreHistoryBadge: View {
    let compound: String?

    static func letter(_ compound: String?) -> String {
        switch compound?.uppercased() {
        case "SOFT": "S"
        case "MEDIUM": "M"
        case "HARD": "H"
        case "INTERMEDIATE": "I"
        case "WET": "W"
        default: "?"
        }
    }

    var body: some View {
        Text(Self.letter(compound))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 19, height: 19)
            .background(.white, in: Circle())
            .overlay(Circle().stroke(.gray.opacity(0.55), lineWidth: 2.5))
            .overlay(Circle().stroke(TyreColor.forCompound(compound), lineWidth: 1.8))
            .accessibilityHidden(true)
    }
}

private struct TyreHistoryFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (index, point) in layout.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), positions)
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
    var showsSessionStatus = false
    var liveSnapshot: LiveTimingSnapshot? = nil

    private var days: [(String, [RaceSession])] {
        var groups: [(String, [RaceSession])] = []
        for session in weekend.sessions {
            let key = Presentation.date(session.start, format: "EEEE d MMM", zone: zone)
            if groups.last?.0 == key { groups[groups.count - 1].1.append(session) }
            else { groups.append((key, [session])) }
        }
        return groups
    }
    func isLive(_ session: RaceSession) -> Bool {
        guard !session.isCancelled, !weekend.isCancelled,
              !(session.isGrandPrix && weekend.winner != nil),
              !(session.isQualifying && weekend.qualifyingWinner != nil),
              let snapshot = liveSnapshot, snapshot.hasFreshTiming(at: now),
              snapshot.meetingName?.caseInsensitiveCompare(weekend.name) == .orderedSame,
              snapshot.sessionName?.caseInsensitiveCompare(session.name) == .orderedSame,
              let start = session.start else { return false }
        return now >= start.addingTimeInterval(-6 * 3600) && now <= start.addingTimeInterval(24 * 3600)
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
                            if showsSessionStatus, let status = SchedulePolicy().sessionStatus(session, in: weekend, now: now, timeZone: zone) {
                                SessionStatusBadge(status: status, live: isLive(session), isGrandPrix: session.isGrandPrix)
                            }
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
            if showsSessionStatus, weekend.sessions.contains(where: {
                guard let status = SchedulePolicy().sessionStatus($0, in: weekend, now: now, timeZone: zone) else { return false }
                return status == .scheduledInProgress || status == .scheduledFinished || status == .startPassed
            }) {
                Text("* Based on the timetable. Delays may affect status.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SessionStatusBadge: View {
    let status: SessionScheduleStatus
    var live = false
    var isGrandPrix = false

    private var title: String {
        if live { return "Ongoing" }
        return switch status {
        case .next: "Next"
        case .scheduledInProgress: "Ongoing*"
        case .scheduledFinished: "Finished*"
        case .startPassed: isGrandPrix ? "Ongoing*" : "Started*"
        case .finished: "Finished"
        case .resultsPending: "Results pending"
        }
    }
    private var color: Color {
        if live { return .green }
        return switch status {
        case .next: Presentation.accent
        case .scheduledInProgress: .green
        case .startPassed: isGrandPrix ? .green : .orange
        case .finished, .scheduledFinished: .secondary
        case .resultsPending: .secondary
        }
    }
    var body: some View {
        Text(title).font(.system(size: 10, weight: .medium))
            .fixedSize().padding(.horizontal, 6).padding(.vertical, 3)
            .foregroundStyle(color).background(color.opacity(0.1), in: Capsule())
            .accessibilityLabel(title.replacingOccurrences(of: "*", with: ", based on timetable"))
    }
}
