import Foundation

struct AppSettings: Codable, Sendable {
    var searchProviderID: String?
    var usesImageSearch = false
    var opensLinksInNewTabs = false
}
protocol SettingsRepository: Sendable {
    func loadSettings() async throws -> AppSettings
    func saveSettings(_ settings: AppSettings) async throws
}

@MainActor
final class SettingsService {
    private let repository: SettingsRepository
    private(set) var current = AppSettings()
    private(set) var isReady = false
    private(set) var isSaving = false
    private(set) var error: String?
    var onChange: (() -> Void)?
    init(repository: SettingsRepository) { self.repository = repository }
    func load() async {
        do { current = try await repository.loadSettings(); isReady = true; error = nil }
        catch { self.error = "설정을 읽지 못했습니다: \(error.localizedDescription)" }
        onChange?()
    }
    func save(_ proposed: AppSettings) async {
        guard isReady, !isSaving else { return }
        isSaving = true; error = nil; onChange?()
        do { try await repository.saveSettings(proposed); current = proposed }
        catch { self.error = "설정을 저장하지 못했습니다. 이전 선택을 유지합니다: \(error.localizedDescription)" }
        isSaving = false; onChange?()
    }
}
