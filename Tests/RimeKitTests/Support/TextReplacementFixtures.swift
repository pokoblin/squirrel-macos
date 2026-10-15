import Foundation
import SQLite3

/// 自造一个和系统 TextReplacements.db 同样表结构的数据库（只有用到的字段）
enum TextReplacementFixtures {
    struct SQLiteError: Error, CustomStringConvertible {
        let description: String
    }

    static func makeDatabase(_ url: URL, _ rows: [(shortcut: String?, phrase: String?, deleted: Int?)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteError(description: "建不了数据库") }
        defer { sqlite3_close(db) }
        let create = "CREATE TABLE ZTEXTREPLACEMENTENTRY (Z_PK INTEGER PRIMARY KEY, ZSHORTCUT VARCHAR, ZPHRASE VARCHAR, ZWASDELETED INTEGER)"
        guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else { throw SQLiteError(description: String(cString: sqlite3_errmsg(db))) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO ZTEXTREPLACEMENTENTRY (ZSHORTCUT, ZPHRASE, ZWASDELETED) VALUES (?, ?, ?)", -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError(description: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            if let s = row.shortcut { sqlite3_bind_text(statement, 1, s, -1, transient) } else { sqlite3_bind_null(statement, 1) }
            if let p = row.phrase { sqlite3_bind_text(statement, 2, p, -1, transient) } else { sqlite3_bind_null(statement, 2) }
            if let d = row.deleted { sqlite3_bind_int(statement, 3, Int32(d)) } else { sqlite3_bind_null(statement, 3) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteError(description: String(cString: sqlite3_errmsg(db))) }
        }
    }
}
