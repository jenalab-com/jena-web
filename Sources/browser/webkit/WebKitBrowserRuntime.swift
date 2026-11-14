import AppKit
import WebKit

typealias ProductBrowserRuntime = WebKitBrowserRuntime

/// System WebKit engine: OS media codecs, persistent default data store, engine-created popups as tabs.
@MainActor
final class WebKitBrowserRuntime: NSObject, BrowserRuntime, BrowserPrivacy, SiteSettingsEngine,
                                  NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    /// Value reported for settings this engine cannot enforce per site.
    static let unsupportedSetting: Int32 = 9

    var onCanTerminate: (() -> Bool)?
    var onReady: (() -> Void)?
    var onPageAdded: ((BrowserPageID, Bool) -> Void)?
    var onEvent: ((BrowserEvent) -> Void)?
    var onTerminationCancelled: (() -> Void)?

    private final class Page {
        let id: BrowserPageID
        let view: WKWebView
        var observations: [NSKeyValueObservation] = []
        var mainStatus = 0
        var hasLoadedDocument = false
        var lastVisitURL: URL?
        var faviconTask: Task<Void, Never>?
        init(id: BrowserPageID, view: WKWebView) { self.id = id; self.view = view }
    }
    private var pages: [BrowserPageID: Page] = [:]
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var nextPage: Int64 = 0
    private var linksInNewTabs = false
    private let linkWorld = WKContentWorld.world(name: "jena.link-policy")
    private lazy var linkScript: String = {
        guard let url = Bundle.main.url(forResource: "link-policy", withExtension: "js") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()
    private lazy var configuration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Sites gate sign-in and media on a known browser; match the installed Safari.
        configuration.applicationNameForUserAgent = "Version/\(Self.safariVersion()) Safari/605.1.15"
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Like Safari: only popups opened by a click reach the app; scripted ones are dropped by the engine.
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }()

    private static func safariVersion() -> String {
        let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
        let parts = ((info?["CFBundleShortVersionString"] as? String) ?? "26.0").split(separator: ".").prefix(2)
        return parts.joined(separator: ".")
    }

    // MARK: Lifecycle

    func run(profile: URL) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        installLinkPolicy()
        DispatchQueue.main.async { [weak self] in self?.onReady?() }
        app.run()
        return 0
    }
    func requestQuit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if onCanTerminate?() ?? true { return .terminateNow }
        onTerminationCancelled?()
        return .terminateCancel
    }

    // MARK: Pages

    func surface(for page: BrowserPageID) -> NSView? { pages[page]?.view }
    func createPage(url: URL, foreground: Bool) {
        let page = addPage(configuration: configuration, foreground: foreground)
        if url.absoluteString != "about:blank" { page.view.load(URLRequest(url: url)) }
    }
    func navigate(_ page: BrowserPageID, to url: URL) {
        guard Self.isWeb(url) else { onEvent?(.failure(page, "HTTP 또는 HTTPS 주소만 열 수 있습니다.")); return }
        pages[page]?.view.load(URLRequest(url: url))
    }
    func perform(_ action: BrowserAction, on page: BrowserPageID) {
        guard let target = pages[page] else { return }
        switch action {
        case .back: target.view.goBack()
        case .forward: target.view.goForward()
        case .reload: target.view.reload()
        case .stop: target.view.stopLoading()
        case .close: close(target)
        }
    }
    private func addPage(configuration: WKWebViewConfiguration, foreground: Bool) -> Page {
        nextPage += 1
        let id = BrowserPageID(rawValue: nextPage)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 640), configuration: configuration)
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { view.isInspectable = true }
        let page = Page(id: id, view: view)
        let state: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.reportState(id) } }
        page.observations = [
            view.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.reportTitle(id) } },
            view.observe(\.url, options: [.new]) { [weak self] _, change in
                let url = change.newValue ?? nil
                Task { @MainActor in self?.reportAddress(id, url: url) }
            },
            view.observe(\.isLoading) { _, _ in state() },
            view.observe(\.canGoBack) { _, _ in state() },
            view.observe(\.canGoForward) { _, _ in state() }]
        pages[id] = page
        onPageAdded?(id, foreground)
        onEvent?(.created(id))
        return page
    }
    private func close(_ page: Page) {
        guard pages.removeValue(forKey: page.id) != nil else { return }
        page.faviconTask?.cancel()
        page.observations.forEach { $0.invalidate() }
        page.view.navigationDelegate = nil; page.view.uiDelegate = nil
        page.view.stopLoading(); page.view.removeFromSuperview()
        onEvent?(.closed(page.id))
    }
    private func page(for view: WKWebView) -> Page? { pages.values.first { $0.view === view } }
    private func reportTitle(_ id: BrowserPageID) {
        guard let page = pages[id] else { return }
        onEvent?(.title(id, page.view.title ?? ""))
    }
    private func reportAddress(_ id: BrowserPageID, url: URL?) {
        guard let page = pages[id], let url else { return }
        onEvent?(.address(id, url.absoluteString))
        if page.hasLoadedDocument, !page.view.isLoading {
            recordVisit(for: page, url: url)
        }
    }
    private func recordVisit(for page: Page, url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              page.lastVisitURL != url else { return }
        page.lastVisitURL = url
        onEvent?(.visit(page.id, url, page.view.title ?? ""))
    }
    private func reportState(_ id: BrowserPageID) {
        guard let view = pages[id]?.view else { return }
        onEvent?(.loading(id, view.isLoading, view.canGoBack, view.canGoForward))
    }
    private func fail(_ view: WKWebView, _ message: String) {
        if let page = page(for: view) { onEvent?(.failure(page.id, message)) }
    }
    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") || url.absoluteString == "about:blank"
    }

    // MARK: Link policy

    func setLinksInNewTabs(_ enabled: Bool) { linksInNewTabs = enabled; installLinkPolicy() }
    private func installLinkPolicy() {
        guard !linkScript.isEmpty else { return }
        let source = linkScript.replacingOccurrences(of: "JENA_ENABLED", with: linksInNewTabs ? "true" : "false")
        let controller = configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: linkWorld))
        for page in pages.values { page.view.evaluateJavaScript(source, in: nil, in: linkWorld) { _ in } }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url else { return .allow }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob", "data"].contains(scheme) { return .allow }
        fail(webView, "이 링크 유형은 아직 앱에서 지원하지 않습니다.")
        return .cancel
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame, let page = page(for: webView) {
            page.mainStatus = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
        }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return navigationResponse.canShowMIMEType && disposition != "attachment" ? .allow : .download
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let page = page(for: webView), let url = webView.url, (200..<400).contains(page.mainStatus),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        page.hasLoadedDocument = true
        loadFavicon(for: page, url: url)
        recordVisit(for: page, url: url)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        page(for: webView)?.hasLoadedDocument = false
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let page = page(for: webView) else { return }
        page.hasLoadedDocument = false
        page.lastVisitURL = nil
        page.faviconTask?.cancel()
        onEvent?(.favicon(page.id, nil))
    }

    /// Loopback, private-range, link-local and single-label names, judged from the host text alone.
    private static func isInternalHost(_ value: String) -> Bool {
        let host = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.contains(":") {
            return host == "::" || host == "::1" || host.hasPrefix("fe80") || host.hasPrefix("fc")
                || host.hasPrefix("fd") || host.hasPrefix("::ffff:")
        }
        if !host.contains(".") || [".localhost", ".local", ".internal", ".lan", ".home.arpa"].contains(where: host.hasSuffix) {
            return true
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let parts = labels.compactMap { Int($0) }
        guard labels.count == 4, parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168), (172, 16...31), (100, 64...127): return true
        default: return false
        }
    }

    private func loadFavicon(for page: Page, url: URL) {
        page.faviconTask?.cancel()
        page.faviconTask = Task { [weak self, weak page] in
            guard let page else { return }
            let script = "Array.from(document.querySelectorAll('link[rel]')).filter(l => l.rel.toLowerCase().split(/\\s+/).includes('icon')).map(l => l.href).slice(0, 8)"
            let links = (try? await page.view.evaluateJavaScript(script, in: nil, in: self?.linkWorld ?? .page)) as? [String] ?? []
            let fallback = URL(string: "/favicon.ico", relativeTo: url)?.absoluteURL
            var candidates = links.compactMap { URL(string: $0) }
            if let fallback { candidates.append(fallback) }
            for candidate in candidates where ["http", "https"].contains(candidate.scheme?.lowercased() ?? "") {
                guard !Task.isCancelled else { return }
                // A public page must not make the app itself request local or private addresses.
                guard let host = candidate.host?.lowercased(),
                      host == url.host?.lowercased() || !Self.isInternalHost(host) else { continue }
                do {
                    let request = URLRequest(url: candidate, timeoutInterval: 10)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                          response.expectedContentLength <= 1_048_576 else { continue }
                    var imageBytes = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        imageBytes.append(byte)
                        if imageBytes.count > 1_048_576 { break }
                    }
                    guard imageBytes.count <= 1_048_576, NSImage(data: imageBytes) != nil else { continue }
                    guard !Task.isCancelled, page.view.url == url,
                          self?.pages[page.id] === page else { return }
                    self?.onEvent?(.favicon(page.id, imageBytes))
                    return
                } catch {
                    if Task.isCancelled { return }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error, in: webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error, in: webView)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail(webView, "페이지 프로세스가 종료됐습니다. 새로고침해주세요.")
    }
    private func report(_ error: Error, in view: WKWebView) {
        let detail = error as NSError
        // Cancelled loads and policy-interrupted frames are not page failures.
        if detail.code == NSURLErrorCancelled || (detail.domain == "WebKitErrorDomain" && detail.code == 102) { return }
        fail(view, error.localizedDescription)
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        retainDownload(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        retainDownload(download)
    }
    private func retainDownload(_ download: WKDownload) {
        downloads[ObjectIdentifier(download)] = download
        download.delegate = self
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "다운로드 저장"
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        let result = await panel.begin()
        let id = ObjectIdentifier(download)
        guard result == .OK, let destination = panel.url else {
            downloads.removeValue(forKey: id)
            return nil
        }
        // WKDownload requires a nonexistent destination; never delete an existing file.
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            downloads.removeValue(forKey: id)
            showDownloadNotice("저장하지 않았습니다", detail: "같은 이름의 파일이 있습니다. 다시 다운로드해 다른 이름을 선택해주세요.")
            return nil
        }
        downloadDestinations[id] = destination
        return destination
    }
    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        downloads.removeValue(forKey: id)
        guard let destination = downloadDestinations.removeValue(forKey: id) else { return }
        let alert = NSAlert()
        alert.messageText = "다운로드 완료"
        alert.informativeText = destination.path
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "Finder에서 보기")
        Task { @MainActor in
            let result: NSApplication.ModalResponse
            if let window = NSApp.keyWindow ?? NSApp.windows.first {
                result = await alert.beginSheetModal(for: window)
            } else { result = alert.runModal() }
            if result == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        downloads.removeValue(forKey: id)
        downloadDestinations.removeValue(forKey: id)
        if (error as NSError).code != NSURLErrorCancelled {
            showDownloadNotice("다운로드 실패", detail: error.localizedDescription)
        }
    }
    private func showDownloadNotice(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    // MARK: Popups, dialogs, permissions

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty, !Self.isWeb(url) {
            fail(webView, "지원하지 않는 주소의 팝업을 차단했습니다."); return nil
        }
        if let origin = origin(of: webView), stored(.popups, origin) == 2 {
            fail(webView, "이 사이트의 팝업을 차단했습니다. 현재 사이트 설정(⌘,)에서 변경할 수 있습니다."); return nil
        }
        // The engine-supplied configuration keeps window.opener, POST bodies and sign-in context.
        let foreground = !navigationAction.modifierFlags.contains(.command)
        return addPage(configuration: configuration, foreground: foreground).view
    }
    func webViewDidClose(_ webView: WKWebView) { if let page = page(for: webView) { close(page) } }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = dialog(from: frame, text: message)
        _ = await present(alert, over: webView)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = dialog(from: frame, text: message)
        alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        return await present(alert, over: webView) == .alertFirstButtonReturn
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = dialog(from: frame, text: prompt)
        let input = NSTextField(string: defaultText ?? ""); input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        return await present(alert, over: webView) == .alertFirstButtonReturn ? input.stringValue : nil
    }
    /// Page-supplied text is always shown under the name of the site that sent it.
    private func dialog(from frame: WKFrameInfo, text: String) -> NSAlert {
        let host = frame.securityOrigin.host
        let alert = NSAlert()
        alert.messageText = host.isEmpty ? "이 페이지의 메시지" : "\(host)의 메시지"
        alert.informativeText = text
        return alert
    }
    private func present(_ alert: NSAlert, over view: WKWebView) async -> NSApplication.ModalResponse {
        guard let window = view.window else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let response: NSApplication.ModalResponse
        if let window = webView.window { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        return response == .OK ? panel.urls : nil
    }
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        var kinds: [SiteSettingKind] = []
        if type == .camera || type == .cameraAndMicrophone { kinds.append(.camera) }
        if type == .microphone || type == .cameraAndMicrophone { kinds.append(.microphone) }
        // Embedded frames are refused per request and never change a stored site decision.
        // Decide by the origin that is asking, and only while it is still the page shown in the tab.
        let port = origin.port == 0 ? "" : ":\(origin.port)"
        let requester = SiteSettingsService.origin(from: "\(origin.protocol)://\(origin.host)\(port)")
        guard frame.isMainFrame, let site = requester, site == self.origin(of: webView),
              kinds.allSatisfy({ stored($0, site) == 1 }) else {
            fail(webView, "카메라·마이크 요청을 보류했습니다. 사이트 설정에서 허용한 뒤 다시 요청해주세요.")
            return .deny
        }
        return .grant
    }

    // MARK: Site settings (stored by the app; the engine has no per-site store)

    private func origin(of view: WKWebView) -> String? { view.url.flatMap { SiteSettingsService.origin(from: $0.absoluteString) } }
    private func key(_ kind: SiteSettingKind) -> String { "siteSettings." + kind.rawValue }
    private func stored(_ kind: SiteSettingKind, _ origin: String) -> Int32 {
        Int32((UserDefaults.standard.dictionary(forKey: key(kind))?[origin] as? Int) ?? 0)
    }
    func siteSetting(origin: String, kind: SiteSettingKind, decision: Int32) throws -> Int32 {
        guard (-1...2).contains(decision), SiteSettingsService.origin(from: origin) == origin else {
            throw NSError(domain: "JenaSiteSettings", code: 1, userInfo: [NSLocalizedDescriptionKey: "사이트 설정을 처리하지 못했습니다. 주소를 확인하고 다시 시도해주세요."])
        }
        guard [.camera, .microphone, .popups].contains(kind) else { return Self.unsupportedSetting }
        if decision >= 0 {
            var values = UserDefaults.standard.dictionary(forKey: key(kind)) ?? [:]
            values[origin] = decision == 0 ? nil : Int(decision)
            UserDefaults.standard.set(values, forKey: key(kind))
        }
        return stored(kind, origin)
    }

    // MARK: Privacy

    func clearWebData(site: SiteDataScope?, cache: Bool) async throws -> String {
        let store = WKWebsiteDataStore.default()
        let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        var results: [String] = []
        if let site {
            // WebKit groups site data by registrable domain, so subdomains are removed together.
            let types = WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes)
            let records = await store.dataRecords(ofTypes: types).filter { record in
                let name = record.displayName.lowercased()
                return site.domain == name || site.domain.hasSuffix("." + name)
            }
            if records.isEmpty { results.append("\(site.domain): 저장된 쿠키·사이트 데이터가 없습니다.") }
            else {
                let names = records.map(\.displayName).joined(separator: ", ")
                await store.removeData(ofTypes: types, for: records)
                results.append("\(names): 쿠키·사이트 데이터 삭제 완료")
            }
        }
        if cache {
            await store.removeData(ofTypes: cacheTypes, modifiedSince: .distantPast)
            results.append("HTTP 캐시: 삭제 완료")
        }
        return results.joined(separator: "\n")
    }
}
