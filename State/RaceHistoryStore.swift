import Foundation
import Observation

@MainActor @Observable
public final class RaceHistoryStore {
    public private(set) var request: RaceHistoryRequest?
    public private(set) var history: RaceHistory?
    public private(set) var isLoading = false
    public private(set) var issue: String?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let repository: any RaceHistoryRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(repository: any RaceHistoryRepository, now: @escaping @Sendable () -> Date = { Date() }) { self.repository = repository; self.now = now }

    public func load(_ selected: RaceHistoryRequest, force: Bool = false) async {
        if request == selected, let task, !force { await task.value; return }
        if request == selected, let history, now().timeIntervalSince(history.updatedAt) >= 0,
           now().timeIntervalSince(history.updatedAt) < (history.laps.isEmpty ? 30 : 3600), !force { return }
        task?.cancel(); generation += 1
        let token = generation
        if request != selected { history = nil }
        request = selected; isLoading = true; issue = nil
        let work = Task { [weak self, repository, now] in
            do {
                if !force, let cached = try await repository.cached(selected) {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.history = cached
                    // Completed historical races can be read without refetching a
                    // full session. Recent snapshots are also reusable offline.
                    if (0..<3600).contains(now().timeIntervalSince(cached.updatedAt)) {
                        self.isLoading = false; self.task = nil; return
                    }
                }
            } catch is CancellationError {
                if let self, self.generation == token { self.isLoading = false; self.task = nil }
                return
            }
            catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.issue = "Saved history could not be read. Downloading a fresh copy."
            }
            do {
                let value = try await repository.fetch(selected)
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if value.laps.isEmpty, self.history?.laps.isEmpty == false {
                    self.issue = "No new lap history was returned. Showing the last saved history."
                } else { self.history = value; self.issue = nil }
            } catch is CancellationError {
                guard let self, self.generation == token else { return }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.issue = error.localizedDescription
            }
            guard let self, self.generation == token else { return }
            self.isLoading = false; self.task = nil
        }
        task = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        if generation == token, work.isCancelled { isLoading = false; task = nil }
    }
    public func cancel() { generation += 1; task?.cancel(); task = nil; isLoading = false }
}
