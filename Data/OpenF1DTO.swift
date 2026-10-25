import Foundation

struct MeetingDTO: Decodable, Sendable {
    let meetingKey: Int
    let meetingName: String
    let circuitShortName: String?
    let countryName: String?
    let location: String?
    let dateStart: Date?
    let year: Int
    let isCancelled: Bool?
}

struct SessionDTO: Decodable, Sendable {
    let sessionKey: Int
    let meetingKey: Int
    let sessionName: String
    let dateStart: Date?
    let dateEnd: Date?
    let year: Int
    let isCancelled: Bool?
}

struct ResultDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let position: Int?
}

struct DriverDTO: Decodable, Sendable {
    let driverNumber: Int
    let sessionKey: Int
    let fullName: String?
    let firstName: String?
    let lastName: String?
    let teamName: String?
    let teamColour: String?

    var name: String {
        let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return fullName ?? "Driver \(driverNumber)"
    }
}

struct DriverChampionshipDTO: Decodable, Sendable {
    let sessionKey: Int
    let driverNumber: Int
    let positionCurrent: Int
    let pointsCurrent: Double
}

struct TeamChampionshipDTO: Decodable, Sendable {
    let sessionKey: Int
    let teamName: String
    let positionCurrent: Int
    let pointsCurrent: Double
}

enum JSONCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { value in
            let string = try value.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: try value.singleValueContainer(), debugDescription: "Invalid timestamp: \(string)")
        }
        return decoder
    }
}
