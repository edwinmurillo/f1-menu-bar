import Foundation

public protocol SeasonCaching: Sendable {
    func load(year: Int) async throws -> SeasonSnapshot?
    func save(_ snapshot: SeasonSnapshot) async throws
}

public enum CacheError: LocalizedError, Sendable {
    case incompatible, tooLarge
    public var errorDescription: String? {
        switch self {
        case .incompatible: "The saved calendar could not be read. A fresh copy will be downloaded."
        case .tooLarge: "The saved calendar exceeded the storage limit."
        }
    }
}

public actor SnapshotCache: SeasonCaching {
    private let directory: URL
    public init(directory: URL) { self.directory = directory.appending(path: "openf1-v1", directoryHint: .isDirectory) }
    private func file(for year: Int) -> URL { directory.appending(path: "\(year).json") }

    public func load(year: Int) throws -> SeasonSnapshot? {
        let path = file(for: year)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4_000_000 else { throw CacheError.tooLarge }
        do {
            let value = try JSONDecoder().decode(SeasonSnapshot.self, from: Data(contentsOf: path))
            guard value.schema == SeasonSnapshot.schemaVersion, value.provider == "openf1", value.year == year else {
                throw CacheError.incompatible
            }
            return value
        } catch { throw CacheError.incompatible }
    }

    public func save(_ snapshot: SeasonSnapshot) throws {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 4_000_000 else { throw CacheError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(for: snapshot.year), options: .atomic)
        // Keep this season and adjacent seasons. Remove only this cache's owned year files.
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard url.pathExtension == "json", let year = Int(url.deletingPathExtension().lastPathComponent), (1900...9999).contains(year),
                  abs(year - snapshot.year) > 1 else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }
}
