import AppKit

@MainActor
final class PrivacyWindowController: NSWindowController {
    private let service: PrivacyService
    private let history = NSButton(checkboxWithTitle: "방문 기록", target: nil, action: nil)
    private let period = NSPopUpButton()
    private let site = NSButton(checkboxWithTitle: "지정 사이트의 쿠키·저장 데이터", target: nil, action: nil)
    private let origin = NSTextField(string: "")
    private let cache = NSButton(checkboxWithTitle: "모든 사이트의 HTTP 캐시", target: nil, action: nil)
    private let remove = NSButton(title: "선택 항목 삭제…", target: nil, action: nil)
    private let feedback = NSTextField(wrappingLabelWithString: "삭제할 항목을 선택해주세요.")
    private var isConfirming = false
    init(service: PrivacyService) {
        self.service = service
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "개인정보 관리"; window.isReleasedWhenClosed = false
        period.addItems(withTitles: ["전체 기간", "최근 1시간", "최근 24시간", "최근 7일"])
        origin.placeholderString = "https://example.com"; origin.setAccessibilityLabel("삭제할 사이트 출처")
        let explanation = NSTextField(wrappingLabelWithString: "기간은 방문 기록에만 적용됩니다.\n사이트 삭제는 입력한 사이트가 속한 도메인 전체(하위 도메인 포함)의 쿠키·로컬 저장소·IndexedDB·서비스 워커를 대상으로 합니다. 로그인과 오프라인 데이터가 사라질 수 있습니다.\n열려 있는 탭은 삭제 후 새로고침해주세요. 북마크와 앱 설정은 유지됩니다.")
        remove.target = self; remove.action = #selector(confirmRemoval)
        let stack = NSStackView(views: [history, period, site, origin, cache, explanation, remove, feedback]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20), stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20), origin.widthAnchor.constraint(equalTo: stack.widthAnchor), explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), feedback.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        window.center(); service.onChange = { [weak self] in self?.render() }
    }
    required init?(coder: NSCoder) { nil }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil) }
    private func render() {
        for control: NSControl in [history, period, site, origin, cache, remove] { control.isEnabled = !service.isBusy && !isConfirming }
        feedback.stringValue = service.isBusy ? "삭제 처리 중…\n" + service.results.joined(separator: "\n") : service.results.joined(separator: "\n")
    }
    @objc private func confirmRemoval() {
        guard !service.isBusy, !isConfirming, let window else { return }
        guard history.state == .on || site.state == .on || cache.state == .on else { feedback.stringValue = "삭제할 항목을 선택해주세요."; return }
        do {
            let scope = site.state == .on ? try SiteDataScope(origin.stringValue) : nil
            let now = Date(); let seconds: [TimeInterval?] = [nil, 3600, 86400, 604800]
            let selection = PrivacySelection(history: history.state == .on, since: seconds[period.indexOfSelectedItem].map { now.addingTimeInterval(-$0) }, through: now, site: scope, cache: cache.state == .on)
            var lines: [String] = []
            if selection.history { lines.append("방문 기록: \(period.titleOfSelectedItem ?? "전체 기간")") }
            if let scope { lines.append("쿠키: \(scope.domain) 및 하위 도메인\n저장 데이터: \(scope.origin)") }
            if selection.cache { lines.append("HTTP 캐시: 모든 사이트") }
            let alert = NSAlert(); alert.messageText = "선택한 데이터를 삭제하시겠습니까?"; alert.informativeText = lines.joined(separator: "\n") + "\n\n삭제 후 되돌릴 수 없습니다."
            alert.addButton(withTitle: "삭제"); alert.addButton(withTitle: "취소")
            isConfirming = true; render()
            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }; self.isConfirming = false; self.render()
                guard response == .alertFirstButtonReturn else { return }
                Task { await self.service.remove(selection) }
            }
        } catch { feedback.stringValue = error.localizedDescription }
    }
}
