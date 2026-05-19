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

    func inTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
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
        var shouldFinalizeOnError = true
        defer {
            if shouldFinalizeOnError {
                sqlite3_finalize(statement)
            }
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
        shouldFinalizeOnError = false
        return statement
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              applied_at_ms INTEGER NOT NULL
            );
            DROP TRIGGER IF EXISTS vault_messages_ai;
            DROP TRIGGER IF EXISTS vault_messages_ad;
            DROP TRIGGER IF EXISTS vault_messages_au;
            DROP TABLE IF EXISTS vault_messages_fts;
            DROP TABLE IF EXISTS vault_messages;
            DROP TABLE IF EXISTS vault_resume_snapshots;
            DROP TABLE IF EXISTS vault_source_state;
            DROP TABLE IF EXISTS vault_section_prefs;
            DROP TABLE IF EXISTS vault_imported_sessions;
            DROP TABLE IF EXISTS vault_deleted_sessions;
            DROP TABLE IF EXISTS vault_sessions;
            CREATE TABLE IF NOT EXISTS agent_sessions (
              id TEXT PRIMARY KEY,
              raw_id TEXT NOT NULL,
              agent TEXT NOT NULL,
              source_kind TEXT NOT NULL,
              source_path TEXT,
              cwd TEXT,
              title TEXT NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              indexed_at_ms INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS agent_sessions_agent_updated_idx ON agent_sessions(agent, updated_at_ms DESC);
            CREATE INDEX IF NOT EXISTS agent_sessions_cwd_updated_idx ON agent_sessions(cwd, updated_at_ms DESC);
            CREATE INDEX IF NOT EXISTS agent_sessions_deleted_updated_idx ON agent_sessions(deleted, updated_at_ms DESC);
            INSERT OR IGNORE INTO schema_migrations(version, applied_at_ms)
            VALUES (2, CAST(strftime('%s','now') AS INTEGER) * 1000);
            """
        )
    }
}

final class ExternalSQLiteDatabase: @unchecked Sendable {
    private let db: OpaquePointer

    init(url: URL, readOnly: Bool = true) throws {
        var pointer: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &pointer, flags, nil) == SQLITE_OK,
              let pointer
        else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open SQLite database"
            if let pointer {
                sqlite3_close(pointer)
            }
            throw VaultSQLiteError.open(message)
        }
        self.db = pointer
        sqlite3_busy_timeout(db, 500)
    }

    deinit {
        sqlite3_close(db)
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
        var shouldFinalizeOnError = true
        defer {
            if shouldFinalizeOnError {
                sqlite3_finalize(statement)
            }
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
        shouldFinalizeOnError = false
        return statement
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

func sqliteIdentifier(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
