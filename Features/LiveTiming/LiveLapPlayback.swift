import Foundation

/// A replay selection stays pinned as new laps arrive; nil follows the stream.
struct LiveLapPlayback {
    private(set) var lap: Int?

    mutating func select(_ value: Double, available: [Int]) {
        lap = available.min { abs(Double($0) - value) < abs(Double($1) - value) }
    }

    mutating func goLive() { lap = nil }
    func displayedLap(latest: Int) -> Int { lap ?? latest }
}
