import Foundation

struct SiteDataScope {
    let origin: String
    let domain: String
    init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host?.lowercased(),
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              host.range(of: #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$"#, options: .regularExpression) != nil else {
            throw PrivacyError.invalidSite
        }
        domain = host
        origin = scheme + "://" + host + (parts.port.map { ":\($0)" } ?? "")
    }
}
enum PrivacyError: LocalizedError {
    case invalidSite
    var errorDescription: String? { "경로 없이 사이트 출처를 입력해주세요. 예: https://example.com" }
}
struct PrivacySelection {
    let history: Bool
    let since: Date?
    let through: Date
    let site: SiteDataScope?
    let cache: Bool
}
@MainActor
protocol BrowserPrivacy: AnyObject {
    func clearWebData(site: SiteDataScope?, cache: Bool) async throws -> String
}
@MainActor
final class PrivacyService {
    private let history: HistoryService
    private let browser: BrowserPrivacy
    private(set) var isBusy = false
    private(set) var results: [String] = []
    var onChange: (() -> Void)?
    init(history: HistoryService, browser: BrowserPrivacy) { self.history = history; self.browser = browser }
    func remove(_ selection: PrivacySelection) async {
        guard !isBusy else { return }
        isBusy = true; results = []; onChange?()
        defer { isBusy = false; onChange?() }
        if selection.history {
            do { try await history.delete(since: selection.since, through: selection.through); results.append("방문 기록: 삭제 완료") }
            catch { results.append("방문 기록: 실패 — \(error.localizedDescription)") }
            onChange?()
        }
        if selection.site != nil || selection.cache {
            do { results.append(try await browser.clearWebData(site: selection.site, cache: selection.cache)) }
            catch { results.append("웹 데이터: \(error.localizedDescription)") }
        }
    }
}
