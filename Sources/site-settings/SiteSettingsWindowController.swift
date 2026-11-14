import AppKit

@MainActor
final class SiteSettingsWindowController: NSWindowController {
    private let service: SiteSettingsService
    private let system = SystemPermissions()
    private let address = NSTextField(string: "")
    private let scope = NSTextField(wrappingLabelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private var statuses: [SiteSettingKind: NSTextField] = [:]
    private var systemStatuses: [SiteSettingKind: NSTextField] = [:]
    private var choices: [SiteSettingKind: NSPopUpButton] = [:]
    private var systemButtons: [NSButton] = []
    private var requestingSystem = false
    init(service: SiteSettingsService) {
        self.service = service
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 790, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "사이트 설정"; window.isReleasedWhenClosed = false
        address.placeholderString = "https://example.com"; address.setAccessibilityLabel("사이트 주소")
        let load = NSButton(title: "불러오기", target: self, action: #selector(loadSite))
        let input = NSStackView(views: [address, load]); input.spacing = 8
        let stack = NSStackView(views: [input, scope]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        for (index, kind) in SiteSettingKind.allCases.enumerated() {
            let name = NSTextField(labelWithString: kind.title); name.widthAnchor.constraint(equalToConstant: 55).isActive = true
            let state = NSTextField(labelWithString: "조회되지 않음"); state.widthAnchor.constraint(equalToConstant: 185).isActive = true; statuses[kind] = state
            let choice = NSPopUpButton(); choice.addItems(withTitles: ["변경…", "기본값으로 복원", "허용", "차단"])
            choice.tag = index; choice.target = self; choice.action = #selector(changeSetting(_:)); choice.widthAnchor.constraint(equalToConstant: 140).isActive = true; choices[kind] = choice
            let os = NSTextField(labelWithString: ""); os.widthAnchor.constraint(equalToConstant: 155).isActive = true; systemStatuses[kind] = os
            let row = NSStackView(views: [name, state, choice, os]); row.spacing = 10
            if kind != .cookies && kind != .popups {
                let button = NSButton(title: kind == .notifications ? "OS 설정" : "OS 권한…", target: self, action: #selector(requestSystem(_:)))
                button.tag = index; row.addArrangedSubview(button); systemButtons.append(button)
            }
            stack.addArrangedSubview(row)
        }
        let note = NSTextField(wrappingLabelWithString: "변경은 표시된 사이트에만 적용하며 앱 설정에 저장됩니다.\n카메라·마이크는 사이트 허용과 macOS 허용이 모두 필요합니다. 미허용 요청은 안내 후 보류하며 iframe 요청은 거절합니다.\n팝업은 기본값·허용에서 클릭으로 연 것만 새 탭으로 엽니다. 클릭 없이 뜨는 자동 팝업은 엔진이 막습니다. 차단하면 로그인 창을 포함한 모든 팝업이 열리지 않습니다.\n위치·알림·쿠키의 사이트별 설정은 현재 엔진(WebKit)에서 지원하지 않습니다.")
        stack.addArrangedSubview(note)
        stack.addArrangedSubview(NSButton(title: "적용값·OS 상태 새로고침", target: self, action: #selector(refresh)))
        stack.addArrangedSubview(feedback)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20), stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20), input.widthAnchor.constraint(equalTo: stack.widthAnchor), note.widthAnchor.constraint(equalTo: stack.widthAnchor), feedback.widthAnchor.constraint(equalTo: stack.widthAnchor), scope.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        window.center(); system.onChange = { [weak self] in self?.render() }; render()
    }
    required init?(coder: NSCoder) { nil }
    func present(address current: String?) {
        if let current, let origin = SiteSettingsService.origin(from: current) { address.stringValue = origin; service.load(origin) }
        render(); showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
    private func render() {
        scope.stringValue = service.origin.map { "적용 대상: " + $0 } ?? "적용 대상: 선택되지 않음"
        feedback.stringValue = service.message
        for kind in SiteSettingKind.allCases {
            statuses[kind]?.stringValue = service.status(for: kind)
            systemStatuses[kind]?.stringValue = system.status(kind)
            choices[kind]?.isEnabled = service.origin != nil
            choices[kind]?.selectItem(at: 0)
        }
        for button in systemButtons { button.isEnabled = !requestingSystem }
    }
    @objc private func loadSite() { service.load(address.stringValue); render() }
    @objc private func refresh() { if let origin = service.origin { service.load(origin) }; render() }
    @objc private func changeSetting(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem > 0 else { return }
        service.save(kind: SiteSettingKind.allCases[sender.tag], decision: Int32(sender.indexOfSelectedItem - 1)); render()
    }
    @objc private func requestSystem(_ sender: NSButton) {
        guard !requestingSystem else { return }; requestingSystem = true; render()
        let kind = SiteSettingKind.allCases[sender.tag]
        Task { await system.request(kind); requestingSystem = false; render() }
    }
}
