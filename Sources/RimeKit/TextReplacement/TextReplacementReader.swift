import Foundation
import SQLite3

public enum TextReplacementError: Error, Equatable, Sendable, CustomStringConvertible {
    case cannotOpen(String)
    case queryFailed(String)

    public var description: String {
        switch self {
        case .cannotOpen(let message):
            return "读不了 macOS 的文本替换（\(message)）。可以去「系统设置 → 隐私与安全性」检查权限"
        case .queryFailed(let message):
            return "读 macOS 的文本替换失败：\(message)"
        }
    }
}

/// 读 macOS「文本替换」（~/Library/KeyboardServices/TextReplacements.db），只读打开。
/// 只要能在 Rime 里直接打出来的条目：快捷码只有字母（转成小写），内容不含换行和 Tab（verified-facts 第 5 节）。
public struct TextReplacementReader: Sendable {
    public static var defaultDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/KeyboardServices/TextReplacements.db")
    }

    static let query = """
        SELECT ZPHRASE, lower(ZSHORTCUT)
        FROM ZTEXTREPLACEMENTENTRY
        WHERE (ZWASDELETED = 0 OR ZWASDELETED IS NULL)
          AND ZSHORTCUT IS NOT NULL AND ZPHRASE IS NOT NULL AND ZSHORTCUT <> ''
          AND ZSHORTCUT NOT GLOB '*[^A-Za-z]*'
          AND instr(ZPHRASE, char(9)) = 0 AND instr(ZPHRASE, char(10)) = 0 AND instr(ZPHRASE, char(13)) = 0
        ORDER BY lower(ZSHORTCUT), ZPHRASE
        """

    public let database: URL

    public init(database: URL = Self.defaultDatabase) {
        self.database = database
    }

    /// 没有数据库文件时返回空（当作没有文本替换）
    public func read() throws -> [Phrase] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "打不开"
            sqlite3_close(db)
            throw TextReplacementError.cannotOpen(message)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.query, -1, &statement, nil) == SQLITE_OK else {
            throw TextReplacementError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var phrases: [Phrase] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw TextReplacementError.queryFailed(String(cString: sqlite3_errmsg(db))) }
            guard let text = sqlite3_column_text(statement, 0), let code = sqlite3_column_text(statement, 1) else { continue }
            phrases.append(Phrase(text: String(cString: text), code: String(cString: code), weight: 1))
        }
        return phrases
    }
}
