import Foundation

enum SiteSettingKind: String, CaseIterable {
    case camera, microphone, geolocation, notifications, cookies, popups
    var title: String {
        switch self {
        case .camera: return "카메라"
        case .microphone: return "마이크"
        case .geolocation: return "위치"
        case .notifications: return "알림"
        case .cookies: return "쿠키"
        case .popups: return "팝업"
        }
    }
}
@MainActor
protocol SiteSettingsEngine: AnyObject {
    func siteSetting(origin: String, kind: SiteSettingKind, decision: Int32) throws -> Int32
}

@MainActor
final class SiteSettingsService {
    private let engine: SiteSettingsEngine
    private(set) var origin: String?
    private(set) var values: [SiteSettingKind: Int32] = [:]
    private(set) var message = "HTTP/HTTPS 사이트 주소를 입력해주세요."
    init(engine: SiteSettingsEngine) { self.engine = engine }
    static func origin(from address: String) -> String? {
        guard var url = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        url.scheme = scheme; url.host = host.lowercased(); url.path = ""; url.query = nil; url.fragment = nil
        if (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80) { url.port = nil }
        return url.string
    }
    func load(_ address: String) {
        origin = nil; values = [:]
        guard let selected = Self.origin(from: address) else { message = "HTTP 또는 HTTPS 사이트 주소를 입력해주세요."; return }
        do {
            var loaded: [SiteSettingKind: Int32] = [:]
            for kind in SiteSettingKind.allCases { loaded[kind] = try engine.siteSetting(origin: selected, kind: kind, decision: -1) }
            values = loaded; origin = selected; message = "엔진의 현재 적용값입니다. macOS 허용 상태와는 별개입니다."
        } catch { message = error.localizedDescription }
    }
    func save(kind: SiteSettingKind, decision: Int32) {
        guard let origin, (0...2).contains(decision) else { return }
        do {
            let actual = try engine.siteSetting(origin: origin, kind: kind, decision: decision)
            values[kind] = actual
            if actual == 9 { message = "\(kind.title) 설정은 현재 엔진에서 사이트별로 지원하지 않습니다." }
            else if decision != 0 && actual != decision { message = "요청한 값과 엔진 적용값이 다릅니다. 현재 표시값을 확인해주세요." }
            else { message = "\(kind.title) 설정을 적용했습니다. 열린 페이지는 다시 로드해주세요. 진행 중인 사용을 즉시 종료하려면 해당 탭을 닫아주세요." }
        } catch { message = error.localizedDescription }
    }
    func status(for kind: SiteSettingKind) -> String {
        if kind == .popups, let value = values[kind], value != 9 { return value == 2 ? "모두 차단" : "클릭한 팝업 허용" }
        switch values[kind] {
        case 9: return "현재 엔진에서 미지원"
        case 1: return "허용"
        case 2: return "차단"
        case 0, 3: return kind == .cookies ? "기본 정책" : "미허용 · 요청 시 설정 안내"
        case 4: return "세션 동안 허용"
        case .none: return "조회되지 않음"
        default: return "기타 엔진 정책"
        }
    }
}
