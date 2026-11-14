import Foundation

struct Visit: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let visitedAt: Date
}
protocol HistoryRepository: Sendable {
    func recordVisit(_ visit: Visit) async throws
    func listVisits() async throws -> [Visit]
    func deleteVisits(since: Date?, through: Date) async throws
}

@MainActor
final class HistoryService {
    private let repository: HistoryRepository
    private(set) var items: [Visit] = []
    private(set) var error: String?
    private(set) var isDeleting = false
    private(set) var pendingWrites = 0
    private var generation = 0
    var onChange: (() -> Void)?
    var isBusy: Bool { isDeleting || pendingWrites > 0 }
    init(repository: HistoryRepository) { self.repository = repository }
    func record(title: String, url: URL) {
        guard !isDeleting, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { return }
        let epoch = generation
        let visit = Visit(id: UUID().uuidString, title: title.isEmpty ? url.absoluteString : title, url: url, visitedAt: Date())
        pendingWrites += 1
        Task {
            defer { pendingWrites -= 1; onChange?() }
            guard epoch == generation else { return }
            do { try await repository.recordVisit(visit); error = nil }
            catch { self.error = "방문 기록 저장 실패: \(error.localizedDescription)" }
        }
    }
    func reload() async {
        let epoch = generation
        do {
            let loaded = try await repository.listVisits()
            guard epoch == generation else { return }
            items = loaded; error = nil
        } catch { self.error = "방문 기록 읽기 실패: \(error.localizedDescription)" }
        onChange?()
    }
    func delete(since: Date?, through: Date) async throws {
        guard !isDeleting else { throw CocoaError(.fileWriteUnknown) }
        generation += 1; isDeleting = true; onChange?()
        defer { isDeleting = false; onChange?() }
        try await repository.deleteVisits(since: since, through: through)
        items.removeAll { $0.visitedAt <= through && (since == nil || $0.visitedAt >= since!) }
        error = nil
    }
}
