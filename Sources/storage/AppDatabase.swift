import Foundation
import SQLite3

private enum StorageError: LocalizedError {
    case sqlite(Int32), unsupportedSchema, invalidBookmark, invalidVisit, missingBookmark
    var errorDescription: String? {
        switch self {
        case .sqlite(let code): return "로컬 저장소 오류(\(code)). 저장 공간과 파일 접근 권한을 확인해주세요."
        case .unsupportedSchema: return "지원하지 않는 저장소 형식입니다. 원본 파일은 변경하지 않았습니다."
        case .invalidBookmark: return "HTTP 또는 HTTPS 북마크 주소를 확인해주세요."
        case .invalidVisit: return "방문 기록 형식을 읽을 수 없습니다. 원본은 보존합니다."
        case .missingBookmark: return "북마크가 변경되었거나 삭제되었습니다. 목록을 새로고침해주세요."
        }
    }
}

// All SQLite handles and synchronous disk work stay on this dedicated serial queue.
final class AppDatabase: SettingsRepository, BookmarkRepository, HistoryRepository, @unchecked Sendable {
    private let file: URL
    private let queue = DispatchQueue(label: "local.jena.web.app-database", qos: .userInitiated)
    init(file: URL) { self.file = file }

    private func execute<T: Sendable>(_ operation: @escaping @Sendable (Connection) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { let connection = try Connection(file: self.file); continuation.resume(returning: try operation(connection)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func loadSettings() async throws -> AppSettings {
        try await execute { connection in
            let rows = try connection.rows("SELECT value_json FROM app_setting WHERE key = 'preferences'")
            guard let value = rows.first?.first else { return AppSettings() }
            return try JSONDecoder().decode(AppSettings.self, from: Data(value.utf8))
        }
    }
    func saveSettings(_ settings: AppSettings) async throws {
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try await execute { connection in
            try connection.write("INSERT INTO app_setting(key,value_json) VALUES('preferences',?) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json", [json])
        }
    }
    func listBookmarks() async throws -> [Bookmark] {
        try await execute { connection in
            try connection.rows("SELECT id,title,url FROM bookmark ORDER BY updated_at DESC,id").map { row in
                guard row.count == 3, let url = Self.webURL(row[2]) else { throw StorageError.invalidBookmark }
                return Bookmark(id: row[0], title: row[1], url: url)
            }
        }
    }
    func addBookmark(title: String, url: URL) async throws {
        guard Self.webURL(url.absoluteString) != nil else { throw StorageError.invalidBookmark }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try await execute { connection in
            try connection.write("INSERT INTO bookmark(id,title,url,created_at,updated_at) VALUES(?,?,?,strftime('%s','now'),strftime('%s','now')) ON CONFLICT(url) DO UPDATE SET title=excluded.title,updated_at=excluded.updated_at",
                                 [UUID().uuidString, title.isEmpty ? url.absoluteString : title, url.absoluteString])
        }
    }
    func updateBookmark(_ bookmark: Bookmark) async throws {
        guard Self.webURL(bookmark.url.absoluteString) != nil else { throw StorageError.invalidBookmark }
        try await execute { connection in
            try connection.write("UPDATE bookmark SET title=?,url=?,updated_at=strftime('%s','now') WHERE id=?",
                                 [bookmark.title.isEmpty ? bookmark.url.absoluteString : bookmark.title, bookmark.url.absoluteString, bookmark.id])
            guard connection.changes == 1 else { throw StorageError.missingBookmark }
        }
    }
    func deleteBookmark(id: String) async throws {
        try await execute { connection in try connection.write("DELETE FROM bookmark WHERE id=?", [id]) }
    }
    func recordVisit(_ visit: Visit) async throws {
        try await execute { connection in
            try connection.write("INSERT INTO visit(id,title,url,visited_at) VALUES(?,?,?,?)",
                                 [visit.id, visit.title, visit.url.absoluteString, String(visit.visitedAt.timeIntervalSince1970)])
        }
    }
    func listVisits() async throws -> [Visit] {
        try await execute { connection in
            try connection.rows("SELECT id,title,url,visited_at FROM visit ORDER BY visited_at DESC LIMIT 500").map { row in
                guard row.count == 4, let url = Self.webURL(row[2]), let time = Double(row[3]) else { throw StorageError.invalidVisit }
                return Visit(id: row[0], title: row[1], url: url, visitedAt: Date(timeIntervalSince1970: time))
            }
        }
    }
    func deleteVisits(since: Date?, through: Date) async throws {
        try await execute { connection in
            if let since {
                try connection.write("DELETE FROM visit WHERE visited_at >= ? AND visited_at <= ?",
                                     [String(since.timeIntervalSince1970), String(through.timeIntervalSince1970)])
            } else { try connection.write("DELETE FROM visit WHERE visited_at <= ?", [String(through.timeIntervalSince1970)]) }
        }
    }
    private static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private final class Connection {
        private var handle: OpaquePointer?
        var changes: Int32 { sqlite3_changes(handle) }
        init(file: URL) throws {
            let code = sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
            guard code == SQLITE_OK else { sqlite3_close(handle); handle = nil; throw StorageError.sqlite(code) }
            sqlite3_busy_timeout(handle, 5000)
            do {
                let version = try rows("PRAGMA user_version").first?.first ?? "0"
                guard version == "0" || version == "1" || version == "2" else { throw StorageError.unsupportedSchema }
                if version == "0" {
                    try write("BEGIN IMMEDIATE")
                    do {
                        // A concurrent first launch may already have initialized the file.
                        if try rows("PRAGMA user_version").first?.first == "0" {
                            guard try rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").isEmpty else { throw StorageError.unsupportedSchema }
                            try write("CREATE TABLE app_setting(key TEXT PRIMARY KEY,value_json TEXT NOT NULL)")
                            try write("CREATE TABLE bookmark(id TEXT PRIMARY KEY,title TEXT NOT NULL,url TEXT NOT NULL UNIQUE,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)")
                            try write("PRAGMA user_version=1")
                        }
                        try write("COMMIT")
                    } catch { try? write("ROLLBACK"); throw error }
                }
                if try rows("PRAGMA user_version").first?.first == "1" {
                    if version == "1" { try backupBeforeMigration(file: file) }
                    try write("BEGIN IMMEDIATE")
                    do {
                        if try rows("PRAGMA user_version").first?.first == "1" {
                            try write("CREATE TABLE visit(id TEXT PRIMARY KEY,title TEXT NOT NULL,url TEXT NOT NULL,visited_at REAL NOT NULL)")
                            try write("CREATE INDEX visit_by_time ON visit(visited_at)")
                            try write("PRAGMA user_version=2")
                        }
                        try write("COMMIT")
                    } catch { try? write("ROLLBACK"); throw error }
                }
            } catch { sqlite3_close(handle); handle = nil; throw error }
        }
        private func backupBeforeMigration(file: URL) throws {
            let directory = file.deletingLastPathComponent().appendingPathComponent("MigrationBackups", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("before-v2-" + UUID().uuidString + ".sqlite")
            var destination: OpaquePointer?
            let open = sqlite3_open_v2(target.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            guard open == SQLITE_OK else { sqlite3_close(destination); throw StorageError.sqlite(open) }
            defer { sqlite3_close(destination) }
            guard let copy = sqlite3_backup_init(destination, "main", handle, "main") else { throw StorageError.sqlite(sqlite3_errcode(destination)) }
            let step = sqlite3_backup_step(copy, -1); let finish = sqlite3_backup_finish(copy)
            guard step == SQLITE_DONE, finish == SQLITE_OK else { throw StorageError.sqlite(step == SQLITE_DONE ? finish : step) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        deinit { sqlite3_close(handle) }
        private func statement(_ sql: String, _ values: [String]) throws -> OpaquePointer {
            var statement: OpaquePointer?
            let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
            guard code == SQLITE_OK, let statement else { throw StorageError.sqlite(code) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (index, value) in values.enumerated() {
                let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
                guard result == SQLITE_OK else { sqlite3_finalize(statement); throw StorageError.sqlite(result) }
            }
            return statement
        }
        func write(_ sql: String, _ values: [String] = []) throws {
            let statement = try statement(sql, values); defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else { throw StorageError.sqlite(result) }
        }
        func rows(_ sql: String) throws -> [[String]] {
            let statement = try statement(sql, []); defer { sqlite3_finalize(statement) }
            var rows: [[String]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return rows }
                guard result == SQLITE_ROW else { throw StorageError.sqlite(result) }
                rows.append((0..<sqlite3_column_count(statement)).map { index in
                    guard let value = sqlite3_column_text(statement, index) else { return "" }
                    return String(cString: value)
                })
            }
        }
    }
}
