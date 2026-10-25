import Foundation
import F1Core

@main
struct LiveSmoke {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.year, from: Date())
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/live-smoke-cache")
        let cache = SnapshotCache(directory: directory)
        let repository = OpenF1Repository(client: OpenF1Client(), cache: cache)
        let result = try await repository.refresh(year: year, previous: nil) { partial in
            print("Calendar: \(partial.weekends.count); winners: \(partial.weekends.filter { $0.winner != nil }.count); drivers: \(partial.drivers.count); constructors: \(partial.constructors.count)")
        }
        guard !result.weekends.isEmpty else { throw APIError.invalidData("no season calendar") }
        guard result.issues.isEmpty else { throw APIError.invalidData(result.issues.values.joined(separator: "; ")) }
        let restored = try await cache.load(year: year)
        guard restored == result else { throw CacheError.incompatible }
        let summary: [String: Any] = [
            "year": year,
            "weekends": result.weekends.count,
            "cancelled": result.weekends.filter(\.isCancelled).count,
            "winners": result.weekends.filter { $0.winner != nil }.count,
            "drivers": result.drivers.count,
            "constructors": result.constructors.count,
            "standings_after": result.driverContext?.meetingName ?? "Not available",
            "featured": SchedulePolicy().featured(in: result.weekends, now: Date())?.name ?? "Season complete",
            "cache_round_trip": true
        ]
        let json = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
