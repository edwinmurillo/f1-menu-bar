import Foundation

struct TrackLocationDTO: Decodable, Sendable {
    let date: Date
    let driverNumber: Int
    let x: Double
    let y: Double
}

public struct TrackMapPoint: Sendable {
    public let x: Double
    public let y: Double
}

public struct TrackMapSample: Sendable {
    public let seconds: Double
    public let point: TrackMapPoint
}

public struct TrackMapCar: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let abbreviation: String
    public let teamColor: String?
    public let samples: [TrackMapSample]

    public func position(at seconds: Double) -> TrackMapPoint? {
        guard let first = samples.first, let last = samples.last,
              seconds >= first.seconds, seconds <= last.seconds else { return nil }
        var low = 0, high = samples.count - 1
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].seconds < seconds { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return first.point }
        let before = samples[low - 1], after = samples[low]
        let fraction = (seconds - before.seconds) / max(after.seconds - before.seconds, 0.001)
        return TrackMapPoint(x: before.point.x + (after.point.x - before.point.x) * fraction,
                             y: before.point.y + (after.point.y - before.point.y) * fraction)
    }
}

public struct TrackMapReplay: Sendable {
    public let cars: [TrackMapCar]
    public let outline: [TrackMapPoint]
    public let duration: Double
    public let lap: Int
    public let isPreview: Bool

    public static func preview(drivers: [(number: Int, name: String, color: String?)]) -> Self {
        // A deliberately generic closed loop for checking layout and animation offline.
        // Its shape and car positions are illustrative, never presented as race telemetry.
        let outline = (0...120).map { index -> TrackMapPoint in
            let angle = Double(index) / 120 * 2 * Double.pi
            return TrackMapPoint(x: cos(angle) * (1 + 0.19 * cos(3 * angle)) + 0.18 * sin(4 * angle),
                                 y: sin(angle) * (0.72 + 0.12 * sin(5 * angle)))
        }
        let roster = Array(drivers.prefix(22))
        let cars = roster.enumerated().map { index, driver in
            TrackMapCar(id: driver.number, name: driver.name,
                        abbreviation: String(driver.name.split(separator: " ").last ?? "CAR").prefix(3).uppercased(),
                        teamColor: driver.color,
                        samples: (0...120).map { step in
                let point = outline[(step + 120 - (index * 4) % 120) % 120]
                return TrackMapSample(seconds: Double(step) / 120 * 12, point: point)
            })
        }
        return Self(cars: cars, outline: outline, duration: 12, lap: 0, isPreview: true)
    }
}

public actor TrackMapRepository {
    private let client: OpenF1Client
    public init(client: OpenF1Client) { self.client = client }

    public func load(sessionID: Int) async throws -> TrackMapReplay {
        let query = [URLQueryItem(name: "session_key", value: String(sessionID)),
                     URLQueryItem(name: "lap_number", value: "3")]
        let laps: [HistoricalLapDTO] = try await client.get("laps", query: query)
        guard let lap = laps.first(where: { $0.dateStart != nil && (45...140).contains($0.lapDuration ?? 0) }),
              let start = lap.dateStart, let duration = lap.lapDuration else {
            throw APIError.invalidData("No complete third lap is available for this session")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let locations: [TrackLocationDTO] = try await client.get("location", query: [
            URLQueryItem(name: "session_key", value: String(sessionID)),
            URLQueryItem(name: "date>=", value: formatter.string(from: start)),
            URLQueryItem(name: "date<=", value: formatter.string(from: start.addingTimeInterval(duration)))
        ])
        guard locations.count <= 15_000 else { throw APIError.responseTooLarge }
        let roster: [HistoricalDriverDTO] = try await client.get("drivers", query: [URLQueryItem(name: "session_key", value: String(sessionID))])
        let names = Dictionary(roster.map { ($0.driverNumber, $0) }, uniquingKeysWith: { first, _ in first })
        let valid = locations.filter { $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1_000_000 && abs($0.y) < 1_000_000 && ($0.x != 0 || $0.y != 0) }
        let grouped = Dictionary(grouping: valid, by: \.driverNumber)
        let cars = grouped.compactMap { number, points -> TrackMapCar? in
            let sorted = points.sorted { $0.date < $1.date }
            guard sorted.count >= 3 else { return nil }
            let person = names[number]
            return TrackMapCar(id: number, name: person?.fullName ?? "Driver \(number)",
                               abbreviation: person?.nameAcronym ?? String(number), teamColor: person?.teamColour,
                               samples: sorted.map { TrackMapSample(seconds: $0.date.timeIntervalSince(start),
                                                                    point: TrackMapPoint(x: $0.x, y: $0.y)) })
        }.sorted { $0.id < $1.id }
        guard let reference = cars.first(where: { $0.id == lap.driverNumber && $0.samples.count >= 80 })
                ?? cars.max(by: { $0.samples.count < $1.samples.count }),
              reference.samples.count >= 80, cars.count >= 2 else {
            throw APIError.invalidData("Not enough car locations to trace this lap")
        }
        let outline = reference.samples.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element.point : nil }
        return TrackMapReplay(cars: cars, outline: outline, duration: duration, lap: 3, isPreview: false)
    }
}
