import Foundation
import F1Core

private struct BlockedOpenF1: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse { HTTPResponse(data: Data(), status: 401) }
}

@main struct RaceHistorySmoke {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5, let year = Int(args[1]), let meeting = Int(args[2]), let session = Int(args[3]),
              let start = ISO8601DateFormatter().date(from: args[4]) else {
            fatalError("Usage: race-history-smoke YEAR MEETING_ID RACE_SESSION_ID START_ISO8601")
        }
        let request = RaceHistoryRequest(weekend: RaceWeekend(id: meeting, year: year, name: "Selected Grand Prix",
            sessions: [RaceSession(id: session, name: "Race", start: start)]), provider: .openF1)
        let directory = FileManager.default.temporaryDirectory.appending(path: "F1HistorySmoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        for forceFallback in [false, true] {
            let cache = RaceHistoryCache(directory: directory.appending(path: forceFallback ? "fallback" : "primary"))
            let primary = forceFallback ? OpenF1Client(transport: BlockedOpenF1()) : OpenF1Client()
            let repository = HistoricalRaceRepository(openF1: primary, jolpica: JolpicaClient(), cache: cache)
            let history = try await repository.fetch(request)
            guard !history.laps.isEmpty, history.lastLap > 0, !history.drivers.isEmpty else {
                throw NSError(domain: "Smoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "No real lap history returned"])
            }
            let saved = try await repository.cached(request)
            guard saved == history else { throw NSError(domain: "Smoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cache round-trip failed"]) }
            print("\(forceFallback ? "Forced fallback" : "Primary"): \(history.provider.rawValue), \(history.drivers.count) drivers, \(history.laps.count) laps, \(history.laps.flatMap(\.timings).count) timings, \(history.events.count) events, cache verified")
            for issue in history.limitations { print("  \(issue)") }
        }
    }
}
