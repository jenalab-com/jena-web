import Foundation

struct AppPaths {
    let profile: URL
    let database: URL
    static func prepare() throws -> AppPaths {
        guard let identifier = Bundle.main.bundleIdentifier else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let root = support.appendingPathComponent(identifier, isDirectory: true)
        let profile = root.appendingPathComponent("WebProfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let appData = root.appendingPathComponent("AppData", isDirectory: true)
        try FileManager.default.createDirectory(at: appData, withIntermediateDirectories: true)
        return AppPaths(profile: profile, database: appData.appendingPathComponent("app.sqlite"))
    }
}
