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

/// 一次读到的文本替换：能用的条目，和跳过的条数（只记条数，不记内容）
public struct TextReplacementSnapshot: Sendable, Equatable {
    /// 能在 Rime 里打出来的，按快捷码排序；编码是小写的快捷码，权重都是 1
    public let usable: [Phrase]
    /// 快捷码里有数字、符号等（Rime 里打不出来）
    public let badShortcut: Int
    /// 内容是空的、有换行或 Tab、以 # 开头（短语文件里放不下）
    public let badPhrase: Int

    public init(usable: [Phrase], badShortcut: Int, badPhrase: Int) {
        self.usable = usable
        self.badShortcut = badShortcut
        self.badPhrase = badPhrase
    }
}

/// 读 macOS「文本替换」（~/Library/KeyboardServices/TextReplacements.db），只读打开。
/// 只要能在 Rime 里直接打出来的条目：快捷码只有字母（转成小写），内容不含换行和 Tab（verified-facts 第 5 节）。
public struct TextReplacementReader: Sendable {
    public static var defaultDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/KeyboardServices/TextReplacements.db")
    }

    static let query = """
        SELECT ZPHRASE, ZSHORTCUT
        FROM ZTEXTREPLACEMENTENTRY
        WHERE (ZWASDELETED = 0 OR ZWASDELETED IS NULL)
          AND ZSHORTCUT IS NOT NULL AND ZPHRASE IS NOT NULL AND ZSHORTCUT <> ''
        ORDER BY lower(ZSHORTCUT), ZPHRASE
        """

    public let database: URL

    public init(database: URL = Self.defaultDatabase) {
        self.database = database
    }

    /// 能用的条目（没有数据库文件时为空）
    public func read() throws -> [Phrase] {
        try snapshot().usable
    }

    /// 没有数据库文件时为空（当作没有文本替换）
    public func snapshot() throws -> TextReplacementSnapshot {
        // 只有文件确实不存在才当成没有文本替换；没权限等「看不见」的情况要报错，
        // 不然同步开着时会悄悄去掉已经同步的短语（例如以后开了沙盒）
        var info = stat()
        if stat(database.path, &info) != 0 {
            let code = errno
            if code == ENOENT { return TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0) }
            throw TextReplacementError.cannotOpen(String(cString: strerror(code)))
        }
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
        var usable: [Phrase] = []
        var badShortcut = 0
        var badPhrase = 0
        var seen = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw TextReplacementError.queryFailed(String(cString: sqlite3_errmsg(db))) }
            guard let text = sqlite3_column_text(statement, 0), let code = sqlite3_column_text(statement, 1) else { continue }
            let shortcut = String(cString: code)
            // 快捷码只有字母才能在 Rime 里打出来（verified-facts 第 5 节）
            guard shortcut.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                badShortcut += 1
                continue
            }
            let phrase = Phrase(text: String(cString: text), code: shortcut.lowercased(), weight: 1)
            guard phrase.isValid else {
                badPhrase += 1
                continue
            }
            // 快捷码转小写后，只差大小写的同一条只留一条（生成短语时也只算一条）
            guard seen.insert(phrase.text + "\t" + phrase.code).inserted else { continue }
            usable.append(phrase)
        }
        return TextReplacementSnapshot(usable: usable, badShortcut: badShortcut, badPhrase: badPhrase)
    }
}
