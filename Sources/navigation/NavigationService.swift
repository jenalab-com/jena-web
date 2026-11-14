import Foundation

enum NavigationError: LocalizedError {
    case chooseProvider, emptyInput, invalidAddress, unsupportedScheme
    var errorDescription: String? {
        switch self {
        case .chooseProvider: return "검색엔진을 선택해주세요."
        case .emptyInput: return "검색어나 주소를 입력해주세요."
        case .invalidAddress: return "주소를 확인해주세요."
        case .unsupportedScheme: return "HTTP 또는 HTTPS 주소를 입력해주세요."
        }
    }
}
struct NavigationService {
    let search: SearchService
    func resolve(_ input: String, providerID: String?, mode: SearchMode) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NavigationError.emptyInput }
        let lower = text.lowercased()
        if ["javascript:", "data:", "file:", "mailto:", "tel:", "about:"].contains(where: lower.hasPrefix) {
            throw NavigationError.unsupportedScheme
        }
        if text.contains("://") {
            guard let url = URL(string: text), let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()) else { throw NavigationError.unsupportedScheme }
            guard let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { throw NavigationError.invalidAddress }
            return url
        }
        if !text.contains(where: \.isWhitespace), text.contains("."),
           let url = URL(string: "https://" + text), let host = url.host, host.contains("."),
           url.user == nil, url.password == nil { return url }
        return try search.url(query: text, providerID: providerID, mode: mode)
    }
}
