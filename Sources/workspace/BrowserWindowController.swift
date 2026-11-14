import AppKit

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    private let tabs: TabService
    private let runtime: ProductBrowserRuntime
    private let settings: SettingsService
    private let bookmarks: BookmarkService
    var onShowSiteSettings: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onShowPrivacy: (() -> Void)?
    var isAdditionalWorkInProgress: (() -> Bool)?
    private var actionMessage: String?
    private var isAddingBookmark = false
    private let bookmarkButton = BrowserHeaderButton(title: "북마크 추가", target: nil, action: nil)
    private let navigation: NavigationService
    private let address: NSTextField = {
        let field = NSTextField()
        field.cell = BrowserAddressCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        return field
    }()
    private let providers = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let linkMode = NSPopUpButton()
    private let tabStrip = NSStackView()
    private var tabList: BrowserTabListView?
    private let host = NSView()
    private let bookmarkSidebarHost = NSView()
    private var bookmarkSidebarWidth: NSLayoutConstraint?
    private lazy var bookmarkSidebar: BookmarksSidebarController = {
        let sidebar = BookmarksSidebarController(service: bookmarks) { [weak self] url in
            self?.runtime.createPage(url: url, foreground: true)
        }
        sidebar.onClose = { [weak self] in self?.showBookmarks() }
        return sidebar
    }()
    private let status = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "검색어나 웹 주소를 입력하세요")
    private let back = BrowserHeaderButton(title: "뒤로", target: nil, action: nil)
    private let forward = BrowserHeaderButton(title: "앞으로", target: nil, action: nil)
    private let reload = BrowserHeaderButton(title: "새로고침", target: nil, action: nil)
    private var shownPage: BrowserPageID?
    private var lastAddress = ""
    private var displayedTabIDs: Set<BrowserPageID> = []

    init(tabs: TabService, runtime: ProductBrowserRuntime, navigation: NavigationService, settings: SettingsService, bookmarks: BookmarkService) {
        self.tabs = tabs; self.runtime = runtime; self.navigation = navigation
        self.settings = settings; self.bookmarks = bookmarks
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Jena Web"; window.minSize = NSSize(width: 780, height: 520)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        makeContent(); window.center()
        tabs.onChange = { [weak self] in self?.render() }
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()
    }
    required init?(coder: NSCoder) { nil }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func configureIcon(_ button: NSButton, symbol: String, label: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.title = ""
        button.alternateTitle = ""
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        if button.constraints.isEmpty {
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: BrowserHeaderButton.controlHeight).isActive = true
        }
    }
    private func makeContent() {
        guard let content = window?.contentView else { return }
        address.placeholderString = "검색어 또는 https://주소"
        address.target = self; address.action = #selector(submit)
        address.setAccessibilityLabel("검색어 또는 웹 주소")
        providers.addItem(withTitle: "검색엔진 선택")
        for provider in navigation.search.providers {
            providers.addItem(withTitle: provider.name); providers.lastItem?.representedObject = provider.id
        }
        providers.setAccessibilityLabel("검색엔진")
        providers.target = self; providers.action = #selector(changeSettings)
        mode.target = self; mode.action = #selector(changeSettings)
        mode.addItems(withTitles: ["웹", "이미지"]); mode.setAccessibilityLabel("검색 종류")
        linkMode.addItems(withTitles: ["링크: 현재 탭", "링크: 새 탭"])
        linkMode.target = self; linkMode.action = #selector(changeLinkMode)
        back.target = self; back.action = #selector(goBack)
        forward.target = self; forward.action = #selector(goForward)
        reload.target = self; reload.action = #selector(reloadPage)
        configureIcon(back, symbol: "chevron.left", label: "뒤로")
        configureIcon(forward, symbol: "chevron.right", label: "앞으로")
        configureIcon(reload, symbol: "arrow.clockwise", label: "새로고침")
        let addressContainer = BrowserChromeSurface()
        addressContainer.inputField = address
        address.isBordered = false; address.drawsBackground = false
        address.focusRingType = .none
        address.font = .systemFont(ofSize: 13)
        address.usesSingleLineMode = true
        address.translatesAutoresizingMaskIntoConstraints = false
        addressContainer.addSubview(address)
        NSLayoutConstraint.activate([
            address.leadingAnchor.constraint(equalTo: addressContainer.leadingAnchor, constant: 10),
            address.trailingAnchor.constraint(equalTo: addressContainer.trailingAnchor, constant: -10),
            address.topAnchor.constraint(equalTo: addressContainer.topAnchor),
            address.bottomAnchor.constraint(equalTo: addressContainer.bottomAnchor),
            addressContainer.heightAnchor.constraint(equalToConstant: BrowserHeaderButton.controlHeight)
        ])
        addressContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for control in [providers, mode, linkMode] {
            control.isBordered = false
            control.font = .systemFont(ofSize: 12)
        }
        let go = BrowserHeaderButton(title: "", target: self, action: #selector(submit))
        configureIcon(go, symbol: "arrow.right", label: "이동")
        let toolbar = NSStackView(views: [back, forward, reload, addressContainer, providers, mode, go])
        toolbar.orientation = .horizontal; toolbar.spacing = 8; toolbar.alignment = .centerY
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabStrip.orientation = .horizontal; tabStrip.spacing = 4; tabStrip.alignment = .centerY
        bookmarkButton.target = self; bookmarkButton.action = #selector(addBookmark)
        configureIcon(bookmarkButton, symbol: "bookmark", label: "북마크 추가")
        let bookmarksButton = BrowserHeaderButton(title: "", target: self, action: #selector(showBookmarks))
        configureIcon(bookmarksButton, symbol: "book.closed", label: "북마크")
        let addTab = BrowserHeaderButton(title: "", target: self, action: #selector(newTab))
        configureIcon(addTab, symbol: "plus", label: "새 탭")
        let tabList = BrowserTabListView(tabs: tabStrip, addButton: addTab)
        self.tabList = tabList
        tabList.heightAnchor.constraint(equalToConstant: BrowserHeaderButton.controlHeight).isActive = true
        let tabRow = NSStackView(views: [tabList, linkMode, bookmarkButton, bookmarksButton])
        tabRow.spacing = 8; tabRow.alignment = .centerY
        tabList.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [toolbar, tabRow])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        bookmarkSidebarHost.translatesAutoresizingMaskIntoConstraints = false
        bookmarkSidebarHost.isHidden = true
        content.addSubview(bookmarkSidebarHost)
        bookmarkSidebarWidth = bookmarkSidebarHost.widthAnchor.constraint(equalToConstant: 0)
        bookmarkSidebarWidth?.isActive = true
        host.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(host)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.isHidden = true
        status.drawsBackground = true
        status.backgroundColor = .windowBackgroundColor
        content.addSubview(status)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tabRow.widthAnchor.constraint(equalTo: stack.widthAnchor), tabRow.heightAnchor.constraint(equalToConstant: BrowserHeaderButton.controlHeight),
            bookmarkSidebarHost.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bookmarkSidebarHost.topAnchor.constraint(equalTo: host.topAnchor),
            bookmarkSidebarHost.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: bookmarkSidebarHost.trailingAnchor),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            host.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            host.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            host.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            status.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            status.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            status.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor),
            status.heightAnchor.constraint(equalToConstant: 20)
        ])
        host.setContentHuggingPriority(.defaultLow, for: .vertical)
        status.lineBreakMode = .byTruncatingTail
        emptyLabel.textColor = .secondaryLabelColor; emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(emptyLabel)
        NSLayoutConstraint.activate([emptyLabel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                                     emptyLabel.centerYAnchor.constraint(equalTo: host.centerYAnchor)])
    }
    func render() {
        let addedIndex = tabs.tabs.lastIndex { !displayedTabIDs.contains($0.id) }
        displayedTabIDs = Set(tabs.tabs.map(\.id))
        for view in tabStrip.arrangedSubviews { tabStrip.removeArrangedSubview(view); view.removeFromSuperview() }
        for tab in tabs.tabs {
            let title = button(tab.title, #selector(selectTab(_:)))
            title.tag = Int(tab.id.rawValue)
            title.isBordered = false
            title.font = .systemFont(ofSize: 12, weight: tab.id == tabs.selectedID ? .medium : .regular)
            title.alignment = .left
            title.contentTintColor = tab.id == tabs.selectedID ? .labelColor : .secondaryLabelColor
            title.lineBreakMode = .byTruncatingTail
            title.toolTip = tab.title
            let favicon = tab.favicon.flatMap { NSImage(data: $0) }
                ?? NSImage(systemSymbolName: tab.address.isEmpty ? "doc" : "globe", accessibilityDescription: nil)
            favicon?.size = NSSize(width: 16, height: 16)
            title.image = favicon
            title.imagePosition = .imageLeading
            title.imageScaling = .scaleProportionallyDown
            let close = NSButton(title: "", target: self, action: #selector(closeTab(_:)))
            close.tag = title.tag
            close.isBordered = false
            close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "탭 닫기")?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
            close.imagePosition = .imageOnly
            close.contentTintColor = .secondaryLabelColor
            close.toolTip = "탭 닫기"
            close.setAccessibilityLabel("탭 닫기: " + tab.title)
            let item = BrowserChromeSurface()
            item.isSelected = tab.id == tabs.selectedID
            for control in [title, close] {
                control.translatesAutoresizingMaskIntoConstraints = false
                item.addSubview(control)
            }
            NSLayoutConstraint.activate([
                item.widthAnchor.constraint(equalToConstant: 180),
                item.heightAnchor.constraint(equalToConstant: BrowserHeaderButton.controlHeight),
                title.leadingAnchor.constraint(equalTo: item.leadingAnchor, constant: 10),
                title.centerYAnchor.constraint(equalTo: item.centerYAnchor),
                title.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -4),
                close.trailingAnchor.constraint(equalTo: item.trailingAnchor, constant: -6),
                close.centerYAnchor.constraint(equalTo: item.centerYAnchor),
                close.widthAnchor.constraint(equalToConstant: 20),
                close.heightAnchor.constraint(equalToConstant: 22)
            ])
            tabStrip.addArrangedSubview(item)
            if let surface = runtime.surface(for: tab.id) {
                if surface.superview !== host { host.addSubview(surface); surface.frame = host.bounds; surface.autoresizingMask = [.width, .height] }
                surface.isHidden = tab.id != tabs.selectedID || tab.address.isEmpty
            }
        }
        if let addedIndex { tabList?.revealTab(at: addedIndex) }
        tabList?.needsLayout = true
        guard let selected = tabs.selected else { return }
        if shownPage != selected.id || lastAddress != selected.address {
            if shownPage != selected.id || address.currentEditor() == nil { address.stringValue = selected.address }
            lastAddress = selected.address; shownPage = selected.id
        }
        emptyLabel.isHidden = !selected.address.isEmpty
        back.isEnabled = selected.canGoBack; forward.isEnabled = selected.canGoForward
        configureIcon(reload, symbol: selected.isLoading ? "xmark" : "arrow.clockwise",
                      label: selected.isLoading ? "중지" : "새로고침")
        reload.isEnabled = selected.isReady; address.isEnabled = selected.isReady
        bookmarkButton.isEnabled = !isAddingBookmark && selected.address.hasPrefix("http")
        status.stringValue = settings.error ?? actionMessage ?? selected.error ?? (!settings.isReady ? "설정 불러오는 중…" : (settings.isSaving ? "설정 저장 중…" : (selected.isLoading ? "불러오는 중…" : "")))
        status.isHidden = status.stringValue.isEmpty
        window?.title = selected.address.isEmpty ? "Jena Web" : selected.title + " — Jena Web"
    }
    @objc func newTab() { tabs.openBlank(); focusAddress() }
    @objc func focusAddress() { window?.makeFirstResponder(address) }
    @objc func closeSelectedTab() { if let id = tabs.selectedID { tabs.close(id) } }
    @objc private func selectTab(_ sender: NSButton) { tabs.select(BrowserPageID(rawValue: Int64(sender.tag))) }
    @objc private func closeTab(_ sender: NSButton) { tabs.close(BrowserPageID(rawValue: Int64(sender.tag))) }
    @objc private func submit() {
        guard settings.isReady, !settings.isSaving else { return }
        actionMessage = nil
        do {
            let url = try navigation.resolve(address.stringValue, providerID: providers.selectedItem?.representedObject as? String,
                                             mode: mode.indexOfSelectedItem == 0 ? .web : .images)
            tabs.navigate(to: url); window?.makeFirstResponder(host)
        } catch { status.stringValue = error.localizedDescription; status.isHidden = false }
    }
    private func applySettings() {
        if !settings.isSaving {
            providers.selectItem(at: 0)
            if let id = settings.current.searchProviderID,
               let index = providers.itemArray.firstIndex(where: { ($0.representedObject as? String) == id }) {
                providers.selectItem(at: index)
            }
            mode.selectItem(at: settings.current.usesImageSearch ? 1 : 0)
            linkMode.selectItem(at: settings.current.opensLinksInNewTabs ? 1 : 0)
            runtime.setLinksInNewTabs(settings.current.opensLinksInNewTabs)
        }
        for control in [providers, mode, linkMode] { control.isEnabled = settings.isReady && !settings.isSaving }
        render()
    }
    @objc private func changeLinkMode() { changeSettings() }
    @objc private func changeSettings() {
        let proposed = AppSettings(searchProviderID: providers.selectedItem?.representedObject as? String,
                                   usesImageSearch: mode.indexOfSelectedItem == 1,
                                   opensLinksInNewTabs: linkMode.indexOfSelectedItem == 1)
        Task { await settings.save(proposed) }
    }
    @objc func reloadSettings() {
        guard !settings.isSaving else { return }
        Task { await settings.load() }
    }
    @objc func showSiteSettings() { onShowSiteSettings?() }
    @objc func showHistory() { onShowHistory?() }
    @objc func showPrivacy() { onShowPrivacy?() }
    @objc func showBookmarks() {
        let opening = bookmarkSidebarHost.isHidden
        if !opening { bookmarkSidebar.view.removeFromSuperview() }
        bookmarkSidebarHost.isHidden = !opening
        bookmarkSidebarWidth?.constant = opening ? 280 : 0
        window?.contentView?.layoutSubtreeIfNeeded()
        if opening {
            let sidebarView = bookmarkSidebar.view
            sidebarView.frame = bookmarkSidebarHost.bounds
            sidebarView.autoresizingMask = [.width, .height]
            bookmarkSidebarHost.addSubview(sidebarView)
            bookmarkSidebar.present()
        }
    }
    @objc func addBookmark() {
        guard !isAddingBookmark, isAdditionalWorkInProgress?() != true else { return }
        guard let selected = tabs.selected, let url = URL(string: selected.address),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            actionMessage = "웹페이지를 연 뒤 북마크에 추가해주세요."; render(); return
        }
        isAddingBookmark = true; actionMessage = "북마크 저장 중…"; render()
        Task {
            let saved = await bookmarks.add(title: selected.title, url: url)
            isAddingBookmark = false
            actionMessage = saved ? "북마크에 저장했습니다." : (bookmarks.error ?? "다른 북마크 작업이 끝난 뒤 다시 시도해주세요.")
            render()
        }
    }
    func canTerminate() -> Bool {
        guard !settings.isSaving, !bookmarks.isBusy, !isAddingBookmark, isAdditionalWorkInProgress?() != true else {
            actionMessage = "저장·삭제 작업이 끝난 뒤 종료해주세요."; render(); return false
        }
        return true
    }
    @objc func goBack() { tabs.perform(.back) }
    @objc func goForward() { tabs.perform(.forward) }
    @objc func reloadPage() { tabs.perform(tabs.selected?.isLoading == true ? .stop : .reload) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { tabs.quit(); return false }
}

/// Shared Jena chrome: quiet rounded surfaces that adapt to the system appearance.
@MainActor
private final class BrowserChromeSurface: NSView {
    weak var inputField: NSTextField?
    var isSelected = false
    override func mouseDown(with event: NSEvent) {
        if let inputField { window?.makeFirstResponder(inputField) }
        else { super.mouseDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isSelected ? 0.10 : 0.04).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}

@MainActor
private final class BrowserHeaderButton: NSButton {
    static let controlHeight: CGFloat = 34
    // Custom backgrounds fill bounds, so layout must use those same bounds.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
    private var isHovered = false
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var isHighlighted: Bool { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isEnabled ? (isHighlighted ? 0.13 : (isHovered ? 0.09 : 0.05)) : 0.03).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        super.draw(dirtyRect)
    }
}

/// Keep the control full height; center only the text and field editor inside it.
@MainActor
private final class BrowserAddressCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let drawing = super.drawingRect(forBounds: rect)
        let textHeight = min(drawing.height, cellSize(forBounds: drawing).height)
        return NSRect(x: drawing.minX, y: drawing.midY - textHeight / 2,
                      width: drawing.width, height: textHeight)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                         delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
                       delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }
}

/// The document width never participates in the window's Auto Layout constraints.
@MainActor
private final class BrowserTabListView: NSView {
    private let scroll = NSScrollView()
    private let tabs: NSStackView
    private let addButton: NSButton
    private var pendingRevealIndex: Int?

    init(tabs: NSStackView, addButton: NSButton) {
        self.tabs = tabs
        self.addButton = addButton
        super.init(frame: .zero)
        scroll.hasHorizontalScroller = true
        scroll.horizontalScroller = BrowserTabScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 16))
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = tabs
        addSubview(scroll)
        addSubview(addButton)
        addButton.removeConstraints(addButton.constraints)
        addButton.translatesAutoresizingMaskIntoConstraints = true
    }
    required init?(coder: NSCoder) { nil }

    func revealTab(at index: Int) {
        pendingRevealIndex = index
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let documentWidth = tabs.fittingSize.width
        let viewportWidth = min(documentWidth, max(0, bounds.width - 40))
        scroll.frame = NSRect(x: 0, y: 0, width: viewportWidth, height: bounds.height)
        tabs.frame = NSRect(x: 0, y: 0, width: documentWidth, height: bounds.height)
        addButton.frame = NSRect(x: viewportWidth + 8,
                                 y: (bounds.height - BrowserHeaderButton.controlHeight) / 2,
                                 width: 32, height: BrowserHeaderButton.controlHeight)
        scroll.contentView.scroll(to: NSPoint(x: min(scroll.contentView.bounds.minX,
                                                    max(0, documentWidth - viewportWidth)), y: 0))
        tabs.layoutSubtreeIfNeeded()
        if viewportWidth > 0, let index = pendingRevealIndex {
            pendingRevealIndex = nil
            if tabs.arrangedSubviews.indices.contains(index) {
                tabs.scrollToVisible(tabs.arrangedSubviews[index].frame)
            }
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// Reduce only the painted thickness, preserving the native drag target and behavior.
@MainActor
private final class BrowserTabScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnob() {
        drawAtHalfHeight { super.drawKnob() }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        drawAtHalfHeight { super.drawKnobSlot(in: slotRect, highlight: flag) }
    }

    private func drawAtHalfHeight(_ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: bounds.midY / 2)
        transform.scaleX(by: 1, yBy: 0.5)
        transform.concat()
        draw()
    }
}
