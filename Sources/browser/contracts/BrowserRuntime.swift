import Foundation

struct BrowserPageID: Hashable { let rawValue: Int64 }
enum BrowserAction: Int32 { case back, forward, reload, stop, close }
enum BrowserEvent {
    case visit(BrowserPageID, URL, String)
    case created(BrowserPageID)
    case closed(BrowserPageID)
    case favicon(BrowserPageID, Data?)
    case title(BrowserPageID, String)
    case address(BrowserPageID, String)
    case loading(BrowserPageID, Bool, Bool, Bool)
    case failure(BrowserPageID, String)
}
@MainActor
protocol BrowserRuntime: AnyObject {
    func createPage(url: URL, foreground: Bool)
    func navigate(_ page: BrowserPageID, to url: URL)
    func perform(_ action: BrowserAction, on page: BrowserPageID)
    func setLinksInNewTabs(_ enabled: Bool)
    func requestQuit()
}
