import Foundation
import Testing
@testable import RimeKit

@Suite struct TextReplacementReaderTests {
    @Test func 只读出能在Rime里打出来的条目() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try TextReplacementFixtures.makeDatabase(db, [
            ("Wx", "微信", 0),            // 快捷码转成小写
            ("abc1", "带数字", 0),         // 快捷码不只是字母：打不出来
            ("hh", "换\n行", 0),
            ("hc", "回\r车", 0),
            ("tb", "制\t表", 0),
            ("sc", "删掉了", 1),
            ("nl", "删除标记是空的", nil),  // 空的删除标记算没删
            (nil, "没有快捷码", 0),
            ("", "快捷码是空的", 0),
            ("xy", nil, 0),
        ])
        let phrases = try TextReplacementReader(database: db).read()
        #expect(phrases == [
            Phrase(text: "删除标记是空的", code: "nl", weight: 1),
            Phrase(text: "微信", code: "wx", weight: 1),
        ])
    }

    @Test func 没有数据库文件就当没有文本替换() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try TextReplacementReader(database: dir.url.appending(path: "none.db")).read() == [])
    }

    @Test func 数据库坏了会报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try Data("这不是数据库".utf8).write(to: db)
        #expect(throws: TextReplacementError.self) { try TextReplacementReader(database: db).read() }
    }

    @Test func 默认读系统的数据库() {
        #expect(TextReplacementReader.defaultDatabase.path.hasSuffix("/Library/KeyboardServices/TextReplacements.db"))
    }

    @Test func 数出跳过的条目() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try TextReplacementFixtures.makeDatabase(db, [
            ("ok", "好", 0),
            ("a1", "带数字", 0),        // 快捷码不只是字母
            ("x-y", "带符号", 0),
            ("hh", "换\n行", 0),        // 内容放不进短语文件
            ("jh", "#开头", 0),
            ("kk", "", 0),
            ("sc", "删掉了", 1),        // 删掉的不算
        ])
        let s = try TextReplacementReader(database: db).snapshot()
        #expect(s == TextReplacementSnapshot(usable: [Phrase(text: "好", code: "ok", weight: 1)], badShortcut: 2, badPhrase: 3))
    }

    @Test func 没有数据库时是空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try TextReplacementReader(database: dir.url.appending(path: "none.db")).snapshot()
                == TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0))
    }
}
