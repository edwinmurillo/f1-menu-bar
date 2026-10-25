import Foundation
import F1Core

private actor LiveProbe {
    private var latest = LiveTimingState()
    private var connected = false
    private var fresh = false
    private var interruptions = 0
    func accept(_ state: LiveTimingState) {
        if state.phase != latest.phase { print("Connection: \(state.phase)") }
        if connected && state.phase != .connected && state.phase != latest.phase { interruptions += 1 }
        latest = state
        connected = connected || state.phase == .connected
        fresh = fresh || state.snapshot.hasFreshTiming(at: Date())
    }
    func report() throws -> Bool {
        let snapshot = latest.snapshot
        let report: [String: Any] = [
            "connected": connected,
            "fresh_timing_observed": fresh,
            "interruptions": interruptions,
            "meeting": snapshot.meetingName ?? "Unknown",
            "session": snapshot.sessionName ?? "Unknown",
            "session_status": snapshot.sessionStatus ?? "Unknown",
            "drivers": snapshot.drivers.count,
            "drivers_with_tyres": snapshot.drivers.filter { $0.currentTyre?.compound != nil }.count,
            "drivers_with_lap_times": snapshot.drivers.filter { $0.lastLap != nil }.count,
            "drivers_with_pit_counts": snapshot.drivers.filter { $0.stops != nil }.count,
            "race_control_messages": snapshot.messages.count,
            "issue": latest.message ?? "None"
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        return connected
    }
}

@main struct LiveTimingSmoke {
    static func main() async throws {
        let probe = LiveProbe()
        let client = F1LiveTimingClient()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await client.run { state in await probe.accept(state) } }
            group.addTask { try? await Task.sleep(for: .seconds(45)) }
            await group.next()
            group.cancelAll()
        }
        let connected = try await probe.report()
        if !connected { exit(1) }
    }
}
