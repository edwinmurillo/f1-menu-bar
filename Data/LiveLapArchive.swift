import Foundation
import CryptoKit

public actor LiveLapArchive {
    private let directory: URL
    private var lastSequence = 0

    public init(directory: URL) {
        self.directory = directory.appending(path: "live-laps-v1", directoryHint: .isDirectory)
    }

    public func latest() throws -> LiveSessionRecording? {
        let file = directory.appending(path: "latest.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_000_000 else { throw CacheError.tooLarge }
        let value = try JSONDecoder().decode(LiveSessionRecording.self, from: Data(contentsOf: file))
        guard value.isValid else { throw CacheError.incompatible }
        return value
    }

    public func save(_ value: LiveSessionRecording, sequence: Int) throws {
        guard sequence > lastSequence else { return }
        guard value.isValid else { throw CacheError.incompatible }
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8_000_000 else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the latest active session available after relaunch. Older sessions
        // remain in separate bounded files for later inspection and recovery.
        let key = SHA256.hash(data: Data(value.sessionID.utf8)).map { String(format: "%02x", $0) }.joined()
        try data.write(to: directory.appending(path: key + ".json"), options: .atomic)
        try data.write(to: directory.appending(path: "latest.json"), options: .atomic)
        let files = (try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])).filter { $0.pathExtension == "json" && $0.lastPathComponent != "latest.json" }
        for old in files.sorted(by: {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }).dropLast(30) where old.lastPathComponent != key + ".json" {
            try FileManager.default.removeItem(at: old)
        }
        lastSequence = sequence
    }
}
