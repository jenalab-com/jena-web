import Foundation

struct Bookmark: Identifiable, Sendable {
    let id: String
    var title: String
    var url: URL
}
protocol BookmarkRepository: Sendable {
    func listBookmarks() async throws -> [Bookmark]
    func addBookmark(title: String, url: URL) async throws
    func updateBookmark(_ bookmark: Bookmark) async throws
    func deleteBookmark(id: String) async throws
}

@MainActor
final class BookmarkService {
    private let repository: BookmarkRepository
    private(set) var items: [Bookmark] = []
    private(set) var isBusy = false
    private(set) var error: String?
    var onChange: (() -> Void)?
    init(repository: BookmarkRepository) { self.repository = repository }
    func reload() async { _ = await perform { } }
    func add(title: String, url: URL) async -> Bool {
        await perform { try await self.repository.addBookmark(title: title, url: url) }
    }
    func update(_ bookmark: Bookmark) async -> Bool {
        await perform { try await self.repository.updateBookmark(bookmark) }
    }
    func delete(id: String) async -> Bool {
        await perform { try await self.repository.deleteBookmark(id: id) }
    }
    private func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; error = nil; onChange?()
        defer { isBusy = false; onChange?() }
        do {
            try await operation()
            items = try await repository.listBookmarks()
            return true
        } catch {
            self.error = "북마크 작업을 완료하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }
}
