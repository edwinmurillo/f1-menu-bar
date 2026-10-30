import Foundation

public actor RaceHistoryCache {
    private let directory: URL
    public init(directory: URL) { self.directory = directory.appending(path: "race-history-v1") }
    private func file(_ request: RaceHistoryRequest, provider: DataProvider) -> URL {
        directory.appending(path: provider.rawValue).appending(path: String(request.weekend.year))
            .appending(path: request.key + ".json")
    }
    public func load(_ request: RaceHistoryRequest) throws -> RaceHistory? {
        var values: [RaceHistory] = []
        var failure: Error?
        for provider in [DataProvider.openF1, .jolpica] {
            let path = file(request, provider: provider)
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            do {
                guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_000_000 else { throw CacheError.tooLarge }
                let value = try JSONDecoder().decode(RaceHistory.self, from: Data(contentsOf: path))
                guard value.isValid, value.provider == provider,
                      value.request == request else { throw CacheError.incompatible }
                values.append(value)
            } catch { failure = error }
        }
        if let value = values.max(by: { $0.updatedAt < $1.updatedAt }) { return value }
        if let failure { throw failure }
        return nil
    }
    public func save(_ value: RaceHistory) throws {
        try Task.checkCancellation()
        guard value.isValid else { throw CacheError.incompatible }
        guard !value.laps.isEmpty else { return }
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8_000_000 else { throw CacheError.tooLarge }
        let path = file(value.request, provider: value.provider)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: path, options: .atomic)
        // Bound this cache's owned JSON files while retaining full seasons when
        // they fit. Never evict the snapshot that was just saved.
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])?
            .allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
        var bytes = try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let oldest = files.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) <
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for old in oldest where bytes > 128_000_000 && old != path {
            let size = try old.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try FileManager.default.removeItem(at: old); bytes -= size
        }
    }
}
