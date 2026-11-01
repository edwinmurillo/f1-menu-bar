import Foundation

/// Conservative points-only clinches. A possible tie never earns a trophy;
/// countback, penalties and calendar changes are not guessed.
public enum ChampionshipClinchPolicy {
    public struct Score: Sendable {
        public let id: String
        public let points: Double
        public init(id: String, points: Double) { self.id = id; self.points = points }
    }
    public static func remainingPoints(in season: SeasonSnapshot, context: ChampionshipContext?, constructors: Bool,
        projectedSession: RaceHistoryRequest? = nil) -> Int? {
        guard season.year >= 2025, !season.weekends.isEmpty, season.issues[.schedule] == nil,
              let context else { return nil }
        let baselines = season.weekends.filter { $0.grandPrix?.id == context.sessionID &&
            $0.name.caseInsensitiveCompare(context.meetingName) == .orderedSame }
        guard baselines.count == 1, let baseline = baselines.first?.grandPrix?.start else { return nil }
        var remaining = 0
        for weekend in season.weekends where !weekend.isCancelled {
            guard !weekend.isMissingFromSchedule, weekend.grandPrix != nil else { return nil }
            for session in weekend.activeSessions where session.isGrandPrix || session.isSprint {
                guard let start = session.start else { return nil }
                guard start > baseline else { continue }
                if let projectedSession, projectedSession.calendarProvider == season.provider,
                   projectedSession.weekend.id == weekend.id, projectedSession.session?.id == session.id { continue }
                remaining += session.isGrandPrix ? (constructors ? 43 : 25) : (constructors ? 15 : 8)
            }
        }
        return remaining
    }
    public static func championID(scores: [Score], remainingPoints: Int?) -> String? {
        guard let remainingPoints, remainingPoints >= 0, scores.count >= 2,
              Set(scores.map(\.id)).count == scores.count,
              scores.allSatisfy({ $0.points.isFinite && $0.points >= 0 }),
              let leader = scores.max(by: { $0.points < $1.points }) else { return nil }
        return scores.filter { $0.id != leader.id }.allSatisfy { leader.points > $0.points + Double(remainingPoints) } ? leader.id : nil
    }
}
