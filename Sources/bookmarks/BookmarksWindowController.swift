import AppKit

@MainActor
final class BookmarksSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onClose: (() -> Void)?
    private var window: NSWindow? { view.window }
    private let service: BookmarkService
    private let openURL: (URL) -> Void
    private let table = NSTableView()
    private let feedback = NSTextField(labelWithString: "")
    private var selectedBookmarkID: String?
    private var buttons: [NSButton] = []

    init(service: BookmarkService, openURL: @escaping (URL) -> Void) {
        self.service = service; self.openURL = openURL
        super.init(nibName: nil, bundle: nil)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 600))
        makeContent()
        service.onChange = { [weak self] in self?.render() }
    }
    required init?(coder: NSCoder) { nil }
    func present() {
        Task { await service.reload() }
    }
    private func makeContent() {
        let content = view
        let heading = NSTextField(labelWithString: "북마크")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "북마크 닫기")!, target: self, action: #selector(closeSidebar))
        close.isBordered = false; close.toolTip = "북마크 닫기"
        let header = NSStackView(views: [heading, NSView(), close])
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.width = 250; column.minWidth = 100
        table.addTableColumn(column)
        table.headerView = nil
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.rowHeight = 44
        table.target = self; table.doubleAction = #selector(openSelected)
        table.setAccessibilityLabel("저장한 북마크")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let definitions: [(String, Selector)] = [("새 탭에서 열기", #selector(openSelected)), ("편집", #selector(editSelected)),
                                               ("삭제", #selector(deleteSelected)), ("새로고침", #selector(reloadList))]
        let symbols = ["arrow.up.right.square", "pencil", "trash", "arrow.clockwise"]
        buttons = definitions.enumerated().map { index, definition in
            let button = NSButton(title: "", target: self, action: definition.1)
            button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: definition.0)
            button.imagePosition = .imageOnly; button.isBordered = false
            button.toolTip = definition.0; button.setAccessibilityLabel(definition.0)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return button
        }
        let actions = NSStackView(views: buttons); actions.spacing = 8
        let stack = NSStackView(views: [header, scroll, actions, feedback]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                                     stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                                     stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
                                     header.widthAnchor.constraint(equalTo: stack.widthAnchor),
                                     scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
                                     scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
                                     feedback.widthAnchor.constraint(equalTo: stack.widthAnchor), feedback.heightAnchor.constraint(equalToConstant: 42)])
        feedback.lineBreakMode = .byWordWrapping
        feedback.maximumNumberOfLines = 2
        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = .secondaryLabelColor
    }
    private var selected: Bookmark? { service.items.indices.contains(table.selectedRow) ? service.items[table.selectedRow] : nil }
    private func render() {
        let selectedID = selectedBookmarkID
        table.reloadData()
        if let index = service.items.firstIndex(where: { $0.id == selectedID }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        feedback.stringValue = service.error ?? (service.isBusy ? "처리 중…" : (service.items.isEmpty ? "저장한 북마크가 없습니다. 탐색 화면에서 현재 페이지를 추가하세요." : "\(service.items.count)개"))
        updateButtons()
    }
    private func updateButtons() {
        for (index, button) in buttons.enumerated() { button.isEnabled = !service.isBusy && (index == 3 || selected != nil) }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { service.items.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard service.items.indices.contains(row) else { return nil }
        let bookmark = service.items[row]
        let title = NSTextField(labelWithString: bookmark.title)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        let address = NSTextField(labelWithString: bookmark.url.absoluteString)
        address.font = .systemFont(ofSize: 11); address.textColor = .secondaryLabelColor
        let row = NSStackView(views: [title, address])
        row.orientation = .vertical; row.alignment = .leading; row.spacing = 3
        for label in [title, address] {
            label.lineBreakMode = .byTruncatingTail
            label.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        }
        row.toolTip = bookmark.url.absoluteString
        return row
    }
    @objc private func closeSidebar() { onClose?() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedBookmarkID = selected?.id; updateButtons()
    }
    @objc private func openSelected() { guard !service.isBusy, let bookmark = selected else { return }; openURL(bookmark.url) }
    @objc private func reloadList() { Task { await service.reload() } }
    @objc private func editSelected() {
        if let bookmark = selected { edit(id: bookmark.id, title: bookmark.title, address: bookmark.url.absoluteString) }
    }
    private func edit(id: String, title draftTitle: String, address draftAddress: String, message: String? = nil) {
        guard let window else { return }
        let title = NSTextField(string: draftTitle); title.setAccessibilityLabel("북마크 이름")
        let address = NSTextField(string: draftAddress); address.setAccessibilityLabel("북마크 주소")
        let fields = NSStackView(views: [NSTextField(labelWithString: "이름"), title, NSTextField(labelWithString: "주소"), address])
        fields.orientation = .vertical; fields.alignment = .leading; fields.spacing = 6
        fields.frame = NSRect(x: 0, y: 0, width: 440, height: 110)
        title.widthAnchor.constraint(equalToConstant: 440).isActive = true
        address.widthAnchor.constraint(equalToConstant: 440).isActive = true
        let alert = NSAlert(); alert.messageText = "북마크 편집"
        alert.informativeText = message ?? "이름과 HTTP/HTTPS 주소를 변경할 수 있습니다."
        alert.accessoryView = fields; alert.addButton(withTitle: "저장"); alert.addButton(withTitle: "취소")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let raw = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = title.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                self.edit(id: id, title: name, address: raw, message: "HTTP 또는 HTTPS 주소를 입력해주세요.")
                return
            }
            Task {
                if !(await self.service.update(Bookmark(id: id, title: name, url: url))) {
                    self.edit(id: id, title: name, address: raw, message: self.service.error)
                }
            }
        }
    }
    @objc private func deleteSelected() {
        guard let bookmark = selected, let window else { return }
        let alert = NSAlert(); alert.messageText = "이 북마크를 삭제하시겠습니까?"; alert.informativeText = bookmark.title
        alert.addButton(withTitle: "삭제"); alert.addButton(withTitle: "취소")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { _ = await self?.service.delete(id: bookmark.id) }
        }
    }
}
