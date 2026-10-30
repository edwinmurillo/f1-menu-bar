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
    @ObservationIgnored private var memory: [String: RaceHistory] = [:]
    @ObservationIgnored private var recent: [String] = []

    public init(repository: any RaceHistoryRepository, now: @escaping @Sendable () -> Date = { Date() }) { self.repository = repository; self.now = now }

    private func reusable(_ value: RaceHistory, for selected: RaceHistoryRequest) -> Bool {
        guard value.request == selected, !value.needsPositionRepair, value.detailsComplete != false else { return false }
        if !value.laps.isEmpty, selected.weekend.winner != nil { return true }
        let age = now().timeIntervalSince(value.updatedAt)
        return age >= 0 && age < (value.laps.isEmpty ? 30 : 3600)
    }
    private func remember(_ value: RaceHistory) {
        memory[value.request.key] = value
        recent.removeAll { $0 == value.request.key }; recent.append(value.request.key)
        // Each disk snapshot is bounded to 8 MB; keep at most four in memory.
        while recent.count > 4 { memory.removeValue(forKey: recent.removeFirst()) }
    }
    private func accept(_ value: RaceHistory, selected: RaceHistoryRequest, token: Int) {
        guard generation == token, request == selected, value.request == selected, !Task.isCancelled else { return }
        if value.detailsComplete == false, let old = history, old.request == selected,
           old.detailsComplete != false, !old.laps.isEmpty, !old.needsPositionRepair { return }
        history = value; remember(value)
    }

    public func load(_ selected: RaceHistoryRequest, force: Bool = false) async {
        if request == selected, let task, !force { await task.value; return }
        task?.cancel(); generation += 1
        let token = generation
        let saved = memory[selected.key].flatMap { $0.request == selected ? $0 : nil }
        if request != selected { history = saved }
        request = selected; issue = nil
        if !force, let value = history, reusable(value, for: selected) { isLoading = false; task = nil; return }
        isLoading = true
        let work = Task { [weak self, repository] in
            do {
                if !force, let cached = try await repository.cached(selected) {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.accept(cached, selected: selected, token: token)
                    if self.reusable(cached, for: selected) {
                        self.isLoading = false; self.task = nil; return
                    }
                }
            } catch is CancellationError {
                if let self, self.generation == token { self.isLoading = false; self.task = nil }
                return
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.issue = "Saved history could not be read. Downloading a fresh copy."
            }
            do {
                let value = try await repository.fetch(selected) { [weak self] preview in
                    await self?.accept(preview, selected: selected, token: token)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if value.laps.isEmpty, self.history?.laps.isEmpty == false {
                    self.issue = "No new lap history was returned. Showing the last saved history."
                } else { self.accept(value, selected: selected, token: token); self.issue = nil }
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
