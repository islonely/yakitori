import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Concrete SQLite-backed `Database`.
///
/// Thread safety is provided by a recursive lock, so a transaction body may
/// safely call back into the database on the same thread.
public final class SQLiteDatabase: Database, @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var transactionDepth = 0
    public let path: String

    public init(path: String) throws {
        self.path = path
        try open()
    }

    public static func inMemory() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: ":memory:")
    }

    /// A temporary on-disk database, useful for isolated tests.
    public static func temporary() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WritingTrackerTests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).sqlite")
        return try SQLiteDatabase(path: url.path)
    }

    private func open() throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw WritingTrackerError.databaseUnavailable(message)
        }
        self.handle = db
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA foreign_keys = ON;")
        if path != ":memory:" {
            // Write-ahead logging uses sidecar files that iCloud Drive syncs
            // independently of the database, which can corrupt it. On a cloud
            // path we use a single-file, fully-synchronous journal instead.
            if Self.isCloudBackedPath(path) {
                try execute("PRAGMA journal_mode = DELETE;")
                try execute("PRAGMA synchronous = FULL;")
            } else {
                try execute("PRAGMA journal_mode = WAL;")
                try execute("PRAGMA synchronous = NORMAL;")
            }
        }
    }

    static func isCloudBackedPath(_ path: String) -> Bool {
        path.contains("com~apple~CloudDocs") || path.contains("Mobile Documents")
    }

    deinit {
        sqlite3_close(handle)
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    @discardableResult
    public func execute(_ sql: String, _ params: SQLParameters = []) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(params, to: stmt)
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw error("step failed during execute")
        }
        return Int(sqlite3_changes(handle))
    }

    public func query(_ sql: String, _ params: SQLParameters = []) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(params, to: stmt)
        var rows: [Row] = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_ROW {
                rows.append(readRow(stmt))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw error("step failed during query")
            }
        }
        return rows
    }

    public func queryOne(_ sql: String, _ params: SQLParameters = []) throws -> Row? {
        try query(sql, params).first
    }

    public func scalar(_ sql: String, _ params: SQLParameters = []) throws -> SQLValue? {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(params, to: stmt)
        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            return value(at: 0, in: stmt)
        } else if result == SQLITE_DONE {
            return nil
        }
        throw error("step failed during scalar")
    }

    public var lastInsertRowID: Int64 {
        lock.lock(); defer { lock.unlock() }
        return sqlite3_last_insert_rowid(handle)
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        let isOuter = transactionDepth == 0
        if isOuter {
            try executeRaw("BEGIN IMMEDIATE;")
        } else {
            try executeRaw("SAVEPOINT wt_sp_\(transactionDepth);")
        }
        transactionDepth += 1
        do {
            let value = try body()
            transactionDepth -= 1
            if isOuter {
                try executeRaw("COMMIT;")
            } else {
                try executeRaw("RELEASE SAVEPOINT wt_sp_\(transactionDepth);")
            }
            return value
        } catch {
            transactionDepth -= 1
            if isOuter {
                try? executeRaw("ROLLBACK;")
            } else {
                try? executeRaw("ROLLBACK TO SAVEPOINT wt_sp_\(transactionDepth);")
                try? executeRaw("RELEASE SAVEPOINT wt_sp_\(transactionDepth);")
            }
            throw error
        }
    }

    // MARK: - Private

    private func executeRaw(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errmsg)
        guard result == SQLITE_OK else {
            let message = errmsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errmsg)
            throw WritingTrackerError.databaseUnavailable(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let stmt else {
            throw error("prepare failed: \(sql)")
        }
        return stmt
    }

    private func bind(_ params: SQLParameters, to stmt: OpaquePointer) throws {
        for (index, param) in params.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch param {
            case .null:
                result = sqlite3_bind_null(stmt, position)
            case .integer(let value):
                result = sqlite3_bind_int64(stmt, position, value)
            case .real(let value):
                result = sqlite3_bind_double(stmt, position, value)
            case .text(let value):
                result = sqlite3_bind_text(stmt, position, value, -1, SQLITE_TRANSIENT)
            case .blob(let data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(stmt, position, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
            }
            guard result == SQLITE_OK else { throw error("bind failed") }
        }
    }

    private func readRow(_ stmt: OpaquePointer) -> Row {
        var storage: [String: SQLValue] = [:]
        let count = sqlite3_column_count(stmt)
        for i in 0..<count {
            let name = String(cString: sqlite3_column_name(stmt, i))
            storage[name] = value(at: i, in: stmt)
        }
        return Row(storage)
    }

    private func value(at index: Int32, in stmt: OpaquePointer) -> SQLValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            if let cString = sqlite3_column_text(stmt, index) {
                return .text(String(cString: cString))
            }
            return .null
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(stmt, index))
            if let pointer = sqlite3_column_blob(stmt, index), length > 0 {
                return .blob(Data(bytes: pointer, count: length))
            }
            return .blob(Data())
        default:
            return .null
        }
    }

    private func error(_ prefix: String) -> WritingTrackerError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return .databaseUnavailable("\(prefix): \(message)")
    }
}
