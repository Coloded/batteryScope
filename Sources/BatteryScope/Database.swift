import Foundation
import SQLite3

/// SQLite owns the history. Legacy JSON is retained untouched after a transactional import.
final class HistoryDatabase {
    private var db: OpaquePointer?
    let url: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL, legacyURL: URL? = nil) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let reason = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Не удалось открыть SQLite"
            if db != nil { sqlite3_close(db); db = nil }
            throw ReaderError.message(reason)
        }
        do {
            sqlite3_busy_timeout(db, 5000)
            try execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            try execute("""
                CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, name TEXT NOT NULL, model TEXT NOT NULL, last_seen REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS samples(id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(id), captured_at REAL NOT NULL, charge REAL, health REAL, cycles REAL, payload BLOB NOT NULL);
                CREATE INDEX IF NOT EXISTS samples_device_date ON samples(device_id, captured_at);
                CREATE TABLE IF NOT EXISTS technical(device_id TEXT PRIMARY KEY, captured_at REAL NOT NULL, payload BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
                PRAGMA user_version=1;
                """)
            if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path), try !importedLegacy() {
                let old = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: legacyURL))
                try transaction {
                    for sample in old { try insert(sample) }
                    try execute("INSERT INTO metadata(key,value) VALUES('legacy_json_imported','1');")
                }
            }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW else { throw ReaderError.message("SQLite: " + String(cString: sqlite3_errmsg(db))) }
    }
    private func execute(_ sql: String) throws { try check(sqlite3_exec(db, sql, nil, nil, nil)) }
    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &stmt, nil))
        guard let stmt else { throw ReaderError.message("SQLite: пустой запрос") }
        defer { sqlite3_finalize(stmt) }; return try body(stmt)
    }
    private func bind(_ value: String, to stmt: OpaquePointer, at index: Int32) throws { try check(sqlite3_bind_text(stmt, index, value, -1, transient)) }
    private func bind(_ value: Double?, to stmt: OpaquePointer, at index: Int32) throws { try check(value.map { sqlite3_bind_double(stmt, index, $0) } ?? sqlite3_bind_null(stmt, index)) }
    private func bind(_ data: Data, to stmt: OpaquePointer, at index: Int32) throws { try data.withUnsafeBytes { try check(sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), transient)) } }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do { try body(); try execute("COMMIT;") } catch { try? execute("ROLLBACK;"); throw error }
    }
    private func importedLegacy() throws -> Bool { try statement("SELECT value FROM metadata WHERE key='legacy_json_imported'") { stmt in let code = sqlite3_step(stmt); try check(code); return code == SQLITE_ROW } }
    private func insert(_ sample: Sample) throws {
        let b = sample.battery
        try statement("INSERT INTO devices VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, model=excluded.model, last_seen=MAX(last_seen,excluded.last_seen)") { stmt in
            try bind(b.id, to: stmt, at: 1); try bind(b.name, to: stmt, at: 2); try bind(b.model, to: stmt, at: 3); try bind(b.date.timeIntervalSince1970, to: stmt, at: 4); try check(sqlite3_step(stmt))
        }
        try statement("INSERT INTO samples VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING") { stmt in
            try bind(sample.id.uuidString, to: stmt, at: 1); try bind(b.id, to: stmt, at: 2); try bind(b.date.timeIntervalSince1970, to: stmt, at: 3)
            try bind(b.percent, to: stmt, at: 4); try bind(b.health, to: stmt, at: 5); try bind(b.cycles, to: stmt, at: 6)
            try bind(JSONEncoder().encode(sample), to: stmt, at: 7); try check(sqlite3_step(stmt))
        }
    }
    func append(_ sample: Sample) throws { try transaction { try insert(sample) } }
    func load() throws -> [Sample] {
        try statement("SELECT payload FROM samples ORDER BY captured_at, id") { stmt in
            var result: [Sample] = []
            while true {
                let code = sqlite3_step(stmt); try check(code); if code == SQLITE_DONE { break }
                let data = Data(bytes: sqlite3_column_blob(stmt, 0)!, count: Int(sqlite3_column_bytes(stmt, 0)))
                result.append(try JSONDecoder().decode(Sample.self, from: data))
            }
            return result
        }
    }
    func saveTechnical(_ record: TechnicalRecord) throws {
        try statement("INSERT INTO technical VALUES(?,?,?) ON CONFLICT(device_id) DO UPDATE SET captured_at=excluded.captured_at,payload=excluded.payload") { stmt in
            try bind(record.deviceID, to: stmt, at: 1); try bind(record.date.timeIntervalSince1970, to: stmt, at: 2); try bind(JSONEncoder().encode(record), to: stmt, at: 3); try check(sqlite3_step(stmt))
        }
    }
    func loadTechnical(_ id: String) throws -> TechnicalRecord? {
        try statement("SELECT payload FROM technical WHERE device_id=?") { stmt in
            try bind(id, to: stmt, at: 1); let code = sqlite3_step(stmt); try check(code); if code == SQLITE_DONE { return nil }
            return try JSONDecoder().decode(TechnicalRecord.self, from: Data(bytes: sqlite3_column_blob(stmt, 0)!, count: Int(sqlite3_column_bytes(stmt, 0))))
        }
    }
}
