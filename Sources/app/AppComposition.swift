import AppKit

@MainActor
final class AppComposition {
    let runtime = ProductBrowserRuntime()
    private let settings: SettingsService
    private let history: HistoryService
    private let privacy: PrivacyService
    private var siteSettingsWindow: SiteSettingsWindowController?
    private var historyWindow: HistoryWindowController?
    private var privacyWindow: PrivacyWindowController?
    private let bookmarks: BookmarkService
    private var tabs: TabService?
    private var window: BrowserWindowController?
    private let navigation: NavigationService
    init(paths: AppPaths) throws {
        let database = AppDatabase(file: paths.database)
        settings = SettingsService(repository: database)
        bookmarks = BookmarkService(repository: database)
        history = HistoryService(repository: database)
        privacy = PrivacyService(history: history, browser: runtime)
        guard let catalog = Bundle.main.url(forResource: "search-providers", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        navigation = NavigationService(search: try SearchService(catalog: catalog))
        runtime.onReady = { [weak self] in self?.startWorkspace() }
    }
    private func startWorkspace() {
        let tabs = TabService(runtime: runtime); self.tabs = tabs
        let window = BrowserWindowController(tabs: tabs, runtime: runtime, navigation: navigation, settings: settings, bookmarks: bookmarks); self.window = window
        runtime.onPageAdded = { [weak tabs] id, foreground in tabs?.add(id, foreground: foreground) }
        runtime.onEvent = { [weak tabs, weak self] event in
            tabs?.receive(event)
            if case let .visit(_, url, title) = event { self?.history.record(title: title, url: url) }
        }
        runtime.onTerminationCancelled = { [weak tabs] in tabs?.cancelQuit() }
        let privacyWindow = PrivacyWindowController(service: privacy); self.privacyWindow = privacyWindow
        let historyWindow = HistoryWindowController(service: history) { [weak self] url in
            self?.runtime.createPage(url: url, foreground: true)
            self?.window?.window?.makeKeyAndOrderFront(nil)
        }
        self.historyWindow = historyWindow
        window.onShowHistory = { [weak historyWindow] in historyWindow?.present() }
        window.onShowPrivacy = { [weak privacyWindow] in privacyWindow?.present() }
        historyWindow.onShowPrivacy = window.onShowPrivacy
        window.isAdditionalWorkInProgress = { [weak self] in
            guard let self else { return false }; return self.history.isBusy || self.privacy.isBusy
        }
        runtime.onCanTerminate = { [weak window] in window?.canTerminate() ?? true }
        let siteSettingsWindow = SiteSettingsWindowController(service: SiteSettingsService(engine: runtime))
        self.siteSettingsWindow = siteSettingsWindow
        window.onShowSiteSettings = { [weak siteSettingsWindow, weak tabs] in siteSettingsWindow?.present(address: tabs?.selected?.address) }
        makeMenu(window: window)
        window.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        // Web addresses given on the command line open as tabs; otherwise start with a blank tab.
        let requested = CommandLine.arguments.dropFirst().compactMap { URL(string: $0) }
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        if requested.isEmpty { tabs.openBlank(); window.focusAddress() }
        else { for url in requested { runtime.createPage(url: url, foreground: true) } }
        Task { await settings.load() }
    }
    private func makeMenu(window: BrowserWindowController) {
        let bar = NSMenu(); NSApp.mainMenu = bar
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(title: "Jena Web"); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "현재 사이트 설정…", action: #selector(BrowserWindowController.showSiteSettings), keyEquivalent: ",").target = window
        appMenu.addItem(withTitle: "설정 다시 불러오기", action: #selector(BrowserWindowController.reloadSettings), keyEquivalent: "").target = window
        appMenu.addItem(withTitle: "Jena Web 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); bar.addItem(fileItem)
        let fileMenu = NSMenu(title: "파일"); fileItem.submenu = fileMenu
        for (title, selector, key) in [("새 탭", #selector(BrowserWindowController.newTab), "t"),
                                       ("탭 닫기", #selector(BrowserWindowController.closeSelectedTab), "w"),
                                       ("주소 입력", #selector(BrowserWindowController.focusAddress), "l"),
                                       ("새로고침", #selector(BrowserWindowController.reloadPage), "r")] {
            fileMenu.addItem(withTitle: title, action: selector, keyEquivalent: key).target = window
        }
        let bookmarkItem = NSMenuItem(); bar.addItem(bookmarkItem)
        let bookmarkMenu = NSMenu(title: "북마크"); bookmarkItem.submenu = bookmarkMenu
        bookmarkMenu.addItem(withTitle: "현재 페이지 추가", action: #selector(BrowserWindowController.addBookmark), keyEquivalent: "d").target = window
        let show = bookmarkMenu.addItem(withTitle: "북마크 보기", action: #selector(BrowserWindowController.showBookmarks), keyEquivalent: "b")
        show.keyEquivalentModifierMask = [.command, .shift]; show.target = window
        let historyItem = NSMenuItem(); bar.addItem(historyItem)
        let historyMenu = NSMenu(title: "방문 기록"); historyItem.submenu = historyMenu
        historyMenu.addItem(withTitle: "방문 기록 보기", action: #selector(BrowserWindowController.showHistory), keyEquivalent: "y").target = window
        historyMenu.addItem(withTitle: "개인정보 관리…", action: #selector(BrowserWindowController.showPrivacy), keyEquivalent: "").target = window
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: "편집"); editItem.submenu = edit
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    }
}
