import AppKit

@MainActor
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let service: HistoryService
    private let openURL: (URL) -> Void
    var onShowPrivacy: (() -> Void)?
    private let table = NSTableView()
    private let feedback = NSTextField(labelWithString: "최근 500건")
    private let formatter: DateFormatter = { let value = DateFormatter(); value.dateStyle = .short; value.timeStyle = .short; return value }()
    init(service: HistoryService, openURL: @escaping (URL) -> Void) {
        self.service = service; self.openURL = openURL
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "방문 기록"; window.isReleasedWhenClosed = false
        for (id, title, width) in [("date", "방문 시간", 150.0), ("title", "제목", 240.0), ("url", "주소", 360.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 28
        table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let actions = NSStackView(views: [NSButton(title: "새 탭에서 열기", target: self, action: #selector(openSelected)), NSButton(title: "새로고침", target: self, action: #selector(reload)), NSButton(title: "개인정보 관리…", target: self, action: #selector(showPrivacy))])
        let stack = NSStackView(views: [scroll, actions, feedback]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)])
        window.center()
        service.onChange = { [weak self] in self?.render() }
    }
    required init?(coder: NSCoder) { nil }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); reload() }
    private func render() { table.reloadData(); feedback.stringValue = service.error ?? "최근 \(service.items.count)건 · 최대 500건 표시" }
    @objc private func reload() { Task { await service.reload() } }
    @objc private func showPrivacy() { onShowPrivacy?() }
    @objc private func openSelected() { guard service.items.indices.contains(table.selectedRow) else { return }; openURL(service.items[table.selectedRow].url) }
    func numberOfRows(in tableView: NSTableView) -> Int { service.items.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard service.items.indices.contains(row) else { return nil }
        let visit = service.items[row]
        let text: String
        switch column?.identifier.rawValue { case "date": text = formatter.string(from: visit.visitedAt); case "url": text = visit.url.absoluteString; default: text = visit.title }
        let label = NSTextField(labelWithString: text); label.lineBreakMode = .byTruncatingTail; label.toolTip = text; return label
    }
}
