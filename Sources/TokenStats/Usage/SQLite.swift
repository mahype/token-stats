import Foundation
import SQLite3

/// Schmaler Wrapper um libsqlite3 – mehr braucht die Aggregat-Datei nicht.
final class SQLiteDB {
    enum Value {
        case int(Int)
        case double(Double)
        case text(String)
        case null
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    private var handle: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw Failure(description: "SQLite: \(path) nicht zu öffnen")
        }
        try exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
    }

    deinit {
        statements.values.forEach { sqlite3_finalize($0) }
        sqlite3_close(handle)
    }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Führt eine Anweisung aus und liefert alle Zeilen. Statements werden wiederverwendet.
    @discardableResult
    func run(_ sql: String, _ bindings: [Value] = []) throws -> [[Value]] {
        let statement = try prepared(sql)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let int): sqlite3_bind_int64(statement, position, Int64(int))
            case .double(let double): sqlite3_bind_double(statement, position, double)
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        var rows: [[Value]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
            case SQLITE_DONE:
                return rows
            default:
                throw error()
            }
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error() }
        statements[sql] = statement
        return statement
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: .int(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT: .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, index)))
        default: .null
        }
    }

    private func error() -> Failure {
        Failure(description: "SQLite: \(String(cString: sqlite3_errmsg(handle)))")
    }
}

extension SQLiteDB.Value {
    var int: Int {
        switch self {
        case .int(let value): value
        case .double(let value): Int(value)
        default: 0
        }
    }

    var double: Double {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: 0
        }
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}
