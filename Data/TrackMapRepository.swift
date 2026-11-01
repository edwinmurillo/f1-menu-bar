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
    public init(x: Double, y: Double) { self.x = x; self.y = y }
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
    public let sourceName: String

    public func positionOnOutline(at fraction: Double) -> TrackMapPoint? {
        guard outline.count >= 2, fraction.isFinite else { return nil }
        let closed = outline + [outline[0]]
        var distances = [0.0]
        for index in 1..<closed.count {
            distances.append(distances[index - 1] + hypot(closed[index].x - closed[index - 1].x,
                                                         closed[index].y - closed[index - 1].y))
        }
        guard let length = distances.last, length > 0 else { return nil }
        let target = fraction.truncatingRemainder(dividingBy: 1) * length
        var low = 0, high = distances.count - 1
        while low < high {
            let middle = (low + high) / 2
            if distances[middle] < target { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return closed[0] }
        let ratio = (target - distances[low - 1]) / max(distances[low] - distances[low - 1], 0.001)
        return TrackMapPoint(x: closed[low - 1].x + (closed[low].x - closed[low - 1].x) * ratio,
                             y: closed[low - 1].y + (closed[low].y - closed[low - 1].y) * ratio)
    }

    public static func preview(drivers: [(number: Int, name: String, color: String?)], outline: [TrackMapPoint]) -> Self {
        guard outline.count >= 3 else { return Self(cars: [], outline: [], duration: 12, lap: 0, isPreview: true, sourceName: "Preview") }
        // The circuit shape is measured geography. Only the car movement is illustrative.
        let closed = outline + [outline[0]]
        var distances = [0.0]
        for index in 1..<closed.count {
            let dx = closed[index].x - closed[index - 1].x
            let dy = closed[index].y - closed[index - 1].y
            distances.append(distances[index - 1] + hypot(dx, dy))
        }
        let length = distances.last ?? 0
        guard length > 0 else { return Self(cars: [], outline: outline, duration: 12, lap: 0, isPreview: true, sourceName: "Preview") }
        func coordinate(at fraction: Double) -> TrackMapPoint {
            let target = fraction.truncatingRemainder(dividingBy: 1) * length
            var low = 0, high = distances.count - 1
            while low < high {
                let middle = (low + high) / 2
                if distances[middle] < target { low = middle + 1 } else { high = middle }
            }
            let next = low
            guard next > 0 else { return closed[0] }
            let ratio = (target - distances[next - 1]) / max(distances[next] - distances[next - 1], 0.001)
            return TrackMapPoint(x: closed[next - 1].x + (closed[next].x - closed[next - 1].x) * ratio,
                                 y: closed[next - 1].y + (closed[next].y - closed[next - 1].y) * ratio)
        }
        let roster = Array(drivers.prefix(22))
        let cars = roster.enumerated().map { index, driver in
            TrackMapCar(id: driver.number, name: driver.name,
                        abbreviation: String(driver.name.split(separator: " ").last ?? "CAR").prefix(3).uppercased(),
                        teamColor: driver.color,
                        samples: (0...120).map { step in
                let point = coordinate(at: Double(step) / 120 + Double(index) / Double(max(roster.count, 1)))
                return TrackMapSample(seconds: Double(step) / 120 * 12, point: point)
            })
        }
        return Self(cars: cars, outline: outline, duration: 12, lap: 0, isPreview: true, sourceName: "Preview")
    }
}

public actor TrackMapRepository {
    private let client: OpenF1Client
    private let recorded: TracingInsightsRepository
    private var cached: [String: TrackMapReplay] = [:]
    public init(client: OpenF1Client, recorded: TracingInsightsRepository = TracingInsightsRepository()) {
        self.client = client; self.recorded = recorded
    }

    public func load(sessionID: Int, weekend: RaceWeekend, session: RaceSession, preferOpenF1: Bool = true) async throws -> TrackMapReplay {
        let key = "\(weekend.year):\(weekend.name):\(session.name)"
        if let replay = cached[key] { return replay }
        let replay: TrackMapReplay
        if preferOpenF1 {
            do { replay = try await load(sessionID: sessionID) }
            catch is CancellationError { throw CancellationError() }
            catch { replay = try await recorded.load(year: weekend.year, weekend: weekend.name, session: session.name) }
        } else {
            replay = try await recorded.load(year: weekend.year, weekend: weekend.name, session: session.name)
        }
        if cached.count >= 3 { cached.removeAll() }
        cached[key] = replay
        return replay
    }

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
        return TrackMapReplay(cars: cars, outline: outline, duration: duration, lap: 3, isPreview: false, sourceName: "OpenF1")
    }
}
