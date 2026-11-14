import Foundation

enum SearchMode: String { case web, images }
struct SearchProvider: Decodable {
    let id: String
    let name: String
    let web: String
    let images: String
}
struct SearchService {
    let providers: [SearchProvider]
    init(catalog: URL) throws { providers = try JSONDecoder().decode([SearchProvider].self, from: Data(contentsOf: catalog)) }
    func url(query: String, providerID: String?, mode: SearchMode) throws -> URL {
        guard let provider = providers.first(where: { $0.id == providerID }) else { throw NavigationError.chooseProvider }
        let template = mode == .web ? provider.web : provider.images
        guard var parts = URLComponents(string: template) else { throw NavigationError.invalidAddress }
        let queryKey = provider.id == "naver" ? "query" : "q"
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: queryKey, value: query)]
        guard let url = parts.url else { throw NavigationError.invalidAddress }
        return url
    }
}
