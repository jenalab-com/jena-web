import Foundation

struct BrowserTab: Identifiable {
    let id: BrowserPageID
    var favicon: Data?
    var title = "새 탭"
    var address = ""
    var isReady = false
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var error: String?
}

@MainActor
final class TabService {
    private let runtime: BrowserRuntime
    private(set) var tabs: [BrowserTab] = []
    private(set) var selectedID: BrowserPageID?
    private(set) var isQuitting = false
    var onChange: (() -> Void)?
    var selected: BrowserTab? { tabs.first { $0.id == selectedID } }

    init(runtime: BrowserRuntime) { self.runtime = runtime }
    func openBlank() {
        guard !isQuitting, let url = URL(string: "about:blank") else { return }
        runtime.createPage(url: url, foreground: true)
    }
    func add(_ id: BrowserPageID, foreground: Bool) {
        tabs.append(BrowserTab(id: id))
        if foreground || selectedID == nil { selectedID = id }
        onChange?()
    }
    func select(_ id: BrowserPageID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id; onChange?()
    }
    func navigate(to url: URL) {
        guard let selected, selected.isReady else { return }
        runtime.navigate(selected.id, to: url)
    }
    func perform(_ action: BrowserAction) {
        guard let selected else { return }
        runtime.perform(action, on: selected.id)
    }
    func close(_ id: BrowserPageID) { runtime.perform(.close, on: id) }
    func quit() { isQuitting = true; runtime.requestQuit() }
    func cancelQuit() { isQuitting = false; if tabs.isEmpty { openBlank() } }
    func receive(_ event: BrowserEvent) {
        switch event {
        case .visit: break
        case .favicon(let id, let image): update(id) { $0.favicon = image }
        case .closed(let id):
            let index = tabs.firstIndex { $0.id == id } ?? 0
            tabs.removeAll { $0.id == id }
            if selectedID == id { selectedID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
            if tabs.isEmpty && !isQuitting { openBlank() }
        case .created(let id): update(id) { $0.isReady = true }
        case .title(let id, let title): update(id) { $0.title = title.isEmpty ? "새 탭" : title }
        case .address(let id, let address): update(id) { $0.address = address == "about:blank" ? "" : address; $0.error = nil }
        case .loading(let id, let loading, let back, let forward):
            update(id) { $0.isLoading = loading; $0.canGoBack = back; $0.canGoForward = forward; if loading { $0.error = nil } }
        case .failure(let id, let message): update(id) { $0.error = message }
        }
        onChange?()
    }
    private func update(_ id: BrowserPageID, _ change: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        change(&tabs[index])
    }
}
