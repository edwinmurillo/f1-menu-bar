import Foundation

private struct RecordedNumber: Decodable, Sendable {
    let value: Double?
    init(from decoder: any Decoder) throws {
        let field = try decoder.singleValueContainer()
        if field.decodeNil() { value = nil }
        else if let number = try? field.decode(Double.self) { value = number.isFinite ? number : nil }
        else if let text = try? field.decode(String.self) { value = Double(text).flatMap { $0.isFinite ? $0 : nil } }
        else { value = nil }
    }
}

private struct RecordedLaps: Decodable, Sendable {
    let lap: [Int]
    let drv: [String]
    let lST: [RecordedNumber]
    let time: [RecordedNumber]
}

private struct RecordedDrivers: Decodable, Sendable {
    struct Driver: Decodable, Sendable {
        let driver: String
        let dn: String
        let fn: String
        let ln: String
        let tc: String?
    }
    let drivers: [Driver]
}

private struct RecordedTelemetry: Decodable, Sendable {
    struct Channels: Decodable, Sendable {
        let time: [Double]
        let x: [Double]
        let y: [Double]
    }
    let tel: Channels
}

public actor TracingInsightsRepository {
    private struct Lap: Sendable {
        let driver: String
        let number: Int
        let start: Double
        let end: Double
        let lap: Int
    }

    private let http: JSONHTTPClient

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        http = JSONHTTPClient(transport: transport, requestSpacing: .milliseconds(150))
    }

    public func load(year: Int, weekend: String, session: String) async throws -> TrackMapReplay {
        guard (2023...2100).contains(year), !weekend.contains("/"), !session.contains("/") else {
            throw APIError.invalidData("Unsupported recorded session path")
        }
        let base = [String(year), "main", weekend, session]
        let table: RecordedLaps = try await get(base + ["session_laptimes.json"])
        guard table.lap.count <= 5000, table.drv.count == table.lap.count,
              table.lST.count == table.lap.count, table.time.count == table.lap.count else {
            throw APIError.invalidData("Invalid recorded lap table")
        }
        let metadata: RecordedDrivers = try await get(base + ["drivers.json"])
        let roster = Dictionary(metadata.drivers.map { ($0.driver, $0) }, uniquingKeysWith: { first, _ in first })
        let laps: [Lap] = table.lap.indices.compactMap { index in
            guard let start = table.lST[index].value, let duration = table.time[index].value,
                  (0...86400).contains(start), (45...180).contains(duration),
                  let number = Int(roster[table.drv[index]]?.dn ?? "") else { return nil }
            return Lap(driver: table.drv[index], number: number, start: start,
                       end: start + duration, lap: table.lap[index])
        }
        let candidates = laps.filter { $0.lap == 3 }
        let windows = candidates.map { candidate in
            (start: candidate.start, active: candidates.filter { $0.start <= candidate.start && $0.end >= candidate.start + 30 })
        }
        guard let best = windows.max(by: { $0.active.count < $1.active.count }), best.active.count >= 2 else {
            throw APIError.invalidData("No simultaneous car telemetry is available for this session")
        }
        let start = best.start
        let end = min(best.active.map(\.end).min() ?? start, start + 140)
        guard end - start >= 30 else { throw APIError.invalidData("The recorded position window is too short") }
        let selected = Array(best.active.prefix(22))
        let loaded = await withTaskGroup(of: (Lap, RecordedTelemetry?).self) { group in
            for lap in selected {
                group.addTask { [self] in
                    let value: RecordedTelemetry? = try? await get(base + [lap.driver, "\(lap.lap)_tel.json"])
                    return (lap, value)
                }
            }
            var results: [(Lap, RecordedTelemetry?)] = []
            for await result in group { results.append(result) }
            return results
        }
        let cars = loaded.compactMap { lap, telemetry -> TrackMapCar? in
            guard let channels = telemetry?.tel, channels.time.count == channels.x.count,
                  channels.time.count == channels.y.count, channels.time.count >= 50,
                  channels.time.count <= 5000 else { return nil }
            let person = roster[lap.driver]
            let samples = channels.time.indices.compactMap { index -> TrackMapSample? in
                let absolute = lap.start + channels.time[index]
                let x = channels.x[index], y = channels.y[index]
                guard absolute >= start, absolute <= end, x.isFinite, y.isFinite,
                      abs(x) < 1_000_000, abs(y) < 1_000_000 else { return nil }
                return TrackMapSample(seconds: absolute - start, point: TrackMapPoint(x: x, y: y))
            }.sorted { $0.seconds < $1.seconds }
            guard samples.count >= 20 else { return nil }
            return TrackMapCar(id: lap.number,
                               name: [person?.fn, person?.ln].compactMap { $0 }.joined(separator: " "),
                               abbreviation: lap.driver, teamColor: person?.tc, samples: samples)
        }.sorted { $0.id < $1.id }
        guard cars.count >= 2,
              let reference = loaded.compactMap({ lap, telemetry -> (Lap, RecordedTelemetry.Channels)? in
                  guard let channels = telemetry?.tel, channels.x.count == channels.y.count,
                        channels.x.count >= 80 else { return nil }
                  return (lap, channels)
              }).max(by: { $0.1.x.count < $1.1.x.count }) else {
            throw APIError.invalidData("Recorded car coordinates were unavailable")
        }
        let outline = reference.1.x.indices.compactMap { index -> TrackMapPoint? in
            guard index.isMultiple(of: 4) else { return nil }
            let x = reference.1.x[index], y = reference.1.y[index]
            return x.isFinite && y.isFinite ? TrackMapPoint(x: x, y: y) : nil
        }
        guard outline.count >= 40 else { throw APIError.invalidData("Recorded circuit trace is incomplete") }
        return TrackMapReplay(cars: cars, outline: outline, duration: end - start,
                              lap: reference.0.lap, isPreview: false, sourceName: "TracingInsights / FastF1")
    }

    private func get<T: Decodable & Sendable>(_ path: [String]) async throws -> T {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "raw.githubusercontent.com"
        url.path = "/TracingInsights/" + path.joined(separator: "/")
        guard let target = url.url else { throw APIError.invalidResponse }
        let data = try await http.get(target)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.invalidData("Invalid recorded telemetry format") }
    }
}
