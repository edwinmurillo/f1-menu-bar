import Foundation

struct HistoricalLapDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let lapNumber: Int
    let dateStart: Date?
    let lapDuration: Double?
}
struct HistoricalPositionDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let date: Date
    let position: Int
}
struct HistoricalStintDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let lapStart: Int
    let lapEnd: Int?
    let compound: String?
    let tyreAgeAtStart: Int?
}
struct HistoricalPitDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let lapNumber: Int
}
struct HistoricalControlDTO: Decodable, Sendable {
    let sessionKey: Int
    let lapNumber: Int?
    let date: Date?
    let category: String?
    let flag: String?
    let message: String
}
struct HistoricalDriverDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let fullName: String?
    let nameAcronym: String?
    let teamName: String?
    let teamColour: String?
}
struct HistoricalIntervalDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let date: Date
    let gapToLeader: HistoricalGapDTO?
}
enum HistoricalGapDTO: Decodable, Sendable {
    case number(Double), text(String)
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .text(try value.decode(String.self)) }
    }
    var normalized: RaceHistoryGap? {
        switch self {
        case .number(let value): value.isFinite && value >= 0 ? .seconds(value) : nil
        case .text(let value):
            if value.uppercased().contains("LAP"), let count = Int(value.filter(\.isNumber)), (1...200).contains(count) { .laps(count) }
            else { nil }
        }
    }
}
