import AppKit
import WebKit

@main
struct HistoryProbe {
    @MainActor static func main() {
        let runtime = WebKitBrowserRuntime()
        var visits: [URL] = []
        var pageID: BrowserPageID?
        runtime.onPageAdded = { id, _ in pageID = id }
        runtime.onEvent = { event in
            if case let .visit(_, url, _) = event { visits.append(url) }
        }
        runtime.onReady = {
            runtime.createPage(url: URL(string: "http://127.0.0.1:18793/start")!, foreground: true)
            Task { @MainActor in
                for _ in 0..<100 where visits.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                guard let id = pageID, let web = runtime.surface(for: id) as? WKWebView, visits.count == 1 else { fatalError("initial load failed") }
                for script in ["history.pushState({}, '', '/pin/1')", "history.replaceState({}, '', '/pin/2')", "location.hash = 'detail'", "history.back()"] {
                    let before = visits.count
                    _ = try! await web.evaluateJavaScript(script)
                    for _ in 0..<50 where visits.count == before { try? await Task.sleep(for: .milliseconds(100)) }
                    precondition(visits.count == before + 1, "missing or duplicate SPA visit")
                }
                let before = visits.count
                _ = try! await web.evaluateJavaScript("history.replaceState({}, '', location.href)")
                try? await Task.sleep(for: .milliseconds(300))
                precondition(visits.count == before, "duplicate URL recorded")
                web.reload()
                for _ in 0..<50 where visits.count == before { try? await Task.sleep(for: .milliseconds(100)) }
                precondition(visits.count == before + 1, "reload not recorded once")
                print("PASS: initial, pushState, replaceState, hash, back, duplicate suppression, reload", visits.map(\.absoluteString))
                exit(0)
            }
        }
        _ = runtime.run(profile: URL(fileURLWithPath: "/tmp"))
    }
}
