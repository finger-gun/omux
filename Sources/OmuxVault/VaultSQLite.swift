import CSQLite
import Foundation

enum VaultSQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)
    case invalidUTF8

    var description: String {
        switch self {
        case .open(let message), .prepare(let message), .step(let message), .bind(let message):
            return message
        case .invalidUTF8:
            return "SQLite returned invalid UTF-8"
        }
    }
}

final class VaultSQLiteDatabase: @unchecked Sendable {
    private let db: OpaquePointer

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer
        else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
            if let pointer {
                sqlite3_close(pointer)
            }
            throw VaultSQLiteError.open(message)
        }
        self.db = pointer
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw VaultSQLiteError.step(message)
        }
    }

    func write(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VaultSQLiteError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    func query<T>(_ sql: String, bindings: [SQLiteBinding] = [], row: (OpaquePointer) throws -> T) throws -> [T] {
        let statement = try prepare(sql, bindings: bindings)
        defer { sqlite3_finalize(statement) }
        var values: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                values.append(try row(statement))
            } else if result == SQLITE_DONE {
                return values
            } else {
                throw VaultSQLiteError.step(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func prepare(_ sql: String, bindings: [SQLiteBinding]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw VaultSQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        for (index, binding) in bindings.enumerated() {
            let result: Int32
            let position = Int32(index + 1)
            switch binding {
            case .string(let value):
                result = sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            case .int(let value):
                result = sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case .bool(let value):
                result = sqlite3_bind_int(statement, position, value ? 1 : 0)
            case .null:
                result = sqlite3_bind_null(statement, position)
            }
            guard result == SQLITE_OK else {
                throw VaultSQLiteError.bind(String(cString: sqlite3_errmsg(db)))
            }
        }
        return statement
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              applied_at_ms INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS vault_sessions (
              id TEXT PRIMARY KEY,
              agent TEXT NOT NULL,
              source_kind TEXT NOT NULL,
              source_path TEXT,
              working_directory TEXT,
              title TEXT NOT NULL,
              model TEXT,
              git_branch TEXT,
              pr_url TEXT,
              modified_at_ms INTEGER NOT NULL,
              preview_available INTEGER NOT NULL,
              resume_available INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS vault_resume_snapshots (
              session_id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              working_directory TEXT,
              launch_command_json TEXT,
              resume_command TEXT,
              registration_id TEXT,
              metadata_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS vault_messages (
              rowid INTEGER PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL,
              turn_id TEXT NOT NULL,
              role TEXT NOT NULL,
              text TEXT NOT NULL,
              ordinal INTEGER NOT NULL,
              modified_at_ms INTEGER NOT NULL,
              UNIQUE(session_id, turn_id)
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS vault_messages_fts USING fts5(
              session_id UNINDEXED,
              turn_id UNINDEXED,
              text,
              content='vault_messages',
              content_rowid='rowid'
            );
            CREATE TABLE IF NOT EXISTS vault_source_state (
              source_key TEXT PRIMARY KEY,
              agent TEXT NOT NULL,
              source_path TEXT NOT NULL,
              modified_at_ms INTEGER NOT NULL,
              adapter_version INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS vault_section_prefs (
              grouping TEXT NOT NULL,
              section_key TEXT NOT NULL,
              sort_index INTEGER NOT NULL,
              PRIMARY KEY (grouping, section_key)
            );
            CREATE TABLE IF NOT EXISTS vault_imported_sessions (
              session_id TEXT PRIMARY KEY,
              imported_at_ms INTEGER NOT NULL
            );
            CREATE TRIGGER IF NOT EXISTS vault_messages_ai AFTER INSERT ON vault_messages BEGIN
              INSERT INTO vault_messages_fts(rowid, session_id, turn_id, text)
              VALUES (new.rowid, new.session_id, new.turn_id, new.text);
            END;
            CREATE TRIGGER IF NOT EXISTS vault_messages_ad AFTER DELETE ON vault_messages BEGIN
              INSERT INTO vault_messages_fts(vault_messages_fts, rowid, session_id, turn_id, text)
              VALUES ('delete', old.rowid, old.session_id, old.turn_id, old.text);
            END;
            CREATE TRIGGER IF NOT EXISTS vault_messages_au AFTER UPDATE ON vault_messages BEGIN
              INSERT INTO vault_messages_fts(vault_messages_fts, rowid, session_id, turn_id, text)
              VALUES ('delete', old.rowid, old.session_id, old.turn_id, old.text);
              INSERT INTO vault_messages_fts(rowid, session_id, turn_id, text)
              VALUES (new.rowid, new.session_id, new.turn_id, new.text);
            END;
            INSERT OR IGNORE INTO schema_migrations(version, applied_at_ms)
            VALUES (1, CAST(strftime('%s','now') AS INTEGER) * 1000);
            """
        )
    }
}

enum SQLiteBinding {
    case string(String)
    case int(Int64)
    case bool(Bool)
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func sqliteText(_ statement: OpaquePointer, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: pointer)
}

func sqliteInt(_ statement: OpaquePointer, _ index: Int32) -> Int64 {
    sqlite3_column_int64(statement, index)
}
