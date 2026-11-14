import AppKit

typealias ProductBrowserRuntime = CEFBrowserRuntime

@MainActor
final class CEFBrowserRuntime: NSObject, BrowserRuntime, BrowserPrivacy, SiteSettingsEngine, @preconcurrency JWBrowserDelegate {
    var onCanTerminate: (() -> Bool)?
    var onReady: (() -> Void)?
    var onPageAdded: ((BrowserPageID, Bool) -> Void)?
    var onEvent: ((BrowserEvent) -> Void)?
    var onTerminationCancelled: (() -> Void)?
    private var surfaces: [BrowserPageID: NSView] = [:]

    func run(profile: URL) -> Int32 {
        profile.path.withCString { JWRun(CommandLine.argc, CommandLine.unsafeArgv, $0, self) }
    }
    func createPage(url: URL, foreground: Bool) {
        _ = url.absoluteString.withCString { JWCreatePage($0, foreground) }
    }
    func navigate(_ page: BrowserPageID, to url: URL) {
        url.absoluteString.withCString { JWNavigate(page.rawValue, $0) }
    }
    func perform(_ action: BrowserAction, on page: BrowserPageID) { JWPageAction(page.rawValue, action.rawValue) }
    func setLinksInNewTabs(_ enabled: Bool) { JWSetLinksInNewTabs(enabled) }
    func requestQuit() { JWRequestQuit() }
    func surface(for page: BrowserPageID) -> NSView? { surfaces[page] }

    func engineReady() { onReady?() }
    func host(forPage page: Int64, foreground: Bool) -> NSView {
        let id = BrowserPageID(rawValue: page)
        let surface = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 640))
        surfaces[id] = surface
        onPageAdded?(id, foreground)
        return surface
    }
    func pageCreated(_ page: Int64) { onEvent?(.created(BrowserPageID(rawValue: page))) }
    func pageClosed(_ page: Int64) {
        let id = BrowserPageID(rawValue: page)
        surfaces.removeValue(forKey: id)?.removeFromSuperview()
        onEvent?(.closed(id))
    }
    func page(_ page: Int64, titleChanged title: String) { onEvent?(.title(BrowserPageID(rawValue: page), title)) }
    func page(_ page: Int64, addressChanged address: String) { onEvent?(.address(BrowserPageID(rawValue: page), address)) }
    func page(_ page: Int64, loading: Bool, back: Bool, forward: Bool) {
        onEvent?(.loading(BrowserPageID(rawValue: page), loading, back, forward))
    }
    func page(_ page: Int64, failed message: String) { onEvent?(.failure(BrowserPageID(rawValue: page), message)) }
    func page(_ page: Int64, visitedURL address: String, title: String) {
        guard let url = URL(string: address) else { return }
        onEvent?(.visit(BrowserPageID(rawValue: page), url, title))
    }
    func clearWebData(site: SiteDataScope?, cache: Bool) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            (site?.origin ?? "").withCString { origin in
                (site?.domain ?? "").withCString { domain in
                    JWClearWebData(origin, domain, cache) { success, message in
                        if success { continuation.resume(returning: message) }
                        else { continuation.resume(throwing: NSError(domain: "JenaPrivacy", code: 1, userInfo: [NSLocalizedDescriptionKey: message])) }
                    }
                }
            }
        }
    }
    func siteSetting(origin: String, kind: SiteSettingKind, decision: Int32) throws -> Int32 {
        let value = origin.withCString { origin in kind.rawValue.withCString { JWSiteSetting(origin, $0, decision) } }
        guard value >= 0 else { throw NSError(domain: "JenaSiteSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "사이트 설정을 처리하지 못했습니다. 삭제 작업 종료 후 주소를 확인하고 다시 시도해주세요."]) }
        return value
    }
    func canTerminate() -> Bool { onCanTerminate?() ?? true }
    func terminationCancelled() { onTerminationCancelled?() }
}
