import Foundation

struct JolpicaEnvelope: Decodable, Sendable {
    let data: JolpicaPage
    enum CodingKeys: String, CodingKey { case data = "MRData" }
}

struct JolpicaPage: Decodable, Sendable {
    let total: String
    let offset: String
    let races: RaceTable?
    let standings: StandingsTable?
    enum CodingKeys: String, CodingKey {
        case total, offset
        case races = "RaceTable", standings = "StandingsTable"
    }
    struct RaceTable: Decodable, Sendable {
        let races: [JolpicaRace]
        enum CodingKeys: String, CodingKey { case races = "Races" }
    }
    struct StandingsTable: Decodable, Sendable {
        let lists: [JolpicaStandings]
        enum CodingKeys: String, CodingKey { case lists = "StandingsLists" }
    }
}

struct JolpicaTime: Decodable, Sendable {
    let date: String
    let time: String?

    func timestamp() throws -> Date? {
        // A date without a time must never become a fictitious midnight session.
        guard let time else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let result = formatter.date(from: "\(date)T\(time)") else {
            throw APIError.invalidData("invalid Jolpica session time")
        }
        return result
    }
}

struct JolpicaRace: Decodable, Sendable {
    let season: String
    let round: String
    let raceName: String
    let circuit: Circuit
    let date: String
    let time: String?
    let firstPractice: JolpicaTime?
    let secondPractice: JolpicaTime?
    let thirdPractice: JolpicaTime?
    let qualifying: JolpicaTime?
    let sprint: JolpicaTime?
    let sprintQualifying: JolpicaTime?
    let sprintShootout: JolpicaTime?
    let results: [Result]?
    let qualifyingResults: [QualifyingResult]?

    enum CodingKeys: String, CodingKey {
        case season, round, raceName, date, time
        case circuit = "Circuit", firstPractice = "FirstPractice", secondPractice = "SecondPractice"
        case thirdPractice = "ThirdPractice", qualifying = "Qualifying", sprint = "Sprint"
        case sprintQualifying = "SprintQualifying", sprintShootout = "SprintShootout", results = "Results"
        case qualifyingResults = "QualifyingResults"
    }
    struct Circuit: Decodable, Sendable {
        let circuitId: String
        let circuitName: String
        let location: Location
        enum CodingKeys: String, CodingKey { case circuitId, circuitName; case location = "Location" }
        struct Location: Decodable, Sendable { let locality: String; let country: String }
    }
    struct Result: Decodable, Sendable {
        let position: String
        let number: String?
        let driver: JolpicaDriver
        let constructor: JolpicaConstructor
        enum CodingKeys: String, CodingKey { case position, number; case driver = "Driver", constructor = "Constructor" }
    }
    struct QualifyingResult: Decodable, Sendable {
        let position: String?
        let number: String?
        let driver: JolpicaDriver
        let constructor: JolpicaConstructor
        enum CodingKeys: String, CodingKey { case position, number; case driver = "Driver", constructor = "Constructor" }
    }
}

struct JolpicaQualifyingEntry: Sendable {
    let race: JolpicaRace
    let result: JolpicaRace.QualifyingResult
}

struct JolpicaDriver: Decodable, Sendable {
    let driverId: String
    let permanentNumber: String?
    let givenName: String
    let familyName: String
    var name: String { "\(givenName) \(familyName)" }
}

struct JolpicaConstructor: Decodable, Sendable {
    let constructorId: String
    let name: String
}

struct JolpicaStandings: Decodable, Sendable {
    let season: String
    let round: String
    let drivers: [JolpicaDriverStanding]?
    let constructors: [JolpicaConstructorStanding]?
    enum CodingKeys: String, CodingKey {
        case season, round
        case drivers = "DriverStandings", constructors = "ConstructorStandings"
    }
}

struct JolpicaDriverStanding: Decodable, Sendable {
    let position: String?
    let positionText: String
    let points: String
    let driver: JolpicaDriver
    let constructors: [JolpicaConstructor]
    enum CodingKeys: String, CodingKey {
        case position, positionText, points
        case driver = "Driver", constructors = "Constructors"
    }
}

struct JolpicaConstructorStanding: Decodable, Sendable {
    let position: String?
    let positionText: String
    let points: String
    let constructor: JolpicaConstructor
    enum CodingKeys: String, CodingKey { case position, positionText, points; case constructor = "Constructor" }
}
