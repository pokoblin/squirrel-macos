import Foundation
import Testing
@testable import RimeKit

/// 编码索引：某个编码下有哪些词、怎么排；排第几 → 权重
struct WubiCodeIndexTests {
    static let userTable = "wubi86_jidian_user"

    static func dict(_ name: String, _ lines: [String], imports: [String] = []) throws -> DictFile {
        var head = "---\nname: \(name)\nversion: \"test\"\nsort: by_weight\n"
        if !imports.isEmpty { head += "import_tables:\n" + imports.map { "  - \($0)\n" }.joined() }
        return try DictFile.parse(head + "...\n" + lines.joined(separator: "\n") + "\n")
    }

    /// 夹具主词库 + 一份个人词库
    static func index(user lines: [String]) throws -> WubiCodeIndex {
        let main = try DictFile.parse(WubiFixtures.mainDict)
        return WubiCodeIndex(main: main, imports: [(name: userTable, file: try dict(userTable, lines))])
    }

    static let fixture = try! index(user: [])

    @Test func 按权重排() throws {
        let idx = try Self.index(user: ["甲\twqiy\t100", "乙\twqiy\t15", "丙\twqiy"])
        #expect(idx.words(for: "wqiy") == [
            IndexedWord(text: "甲", weight: 100, isPersonal: true),
            IndexedWord(text: "你", weight: 20, isPersonal: false),
            IndexedWord(text: "乙", weight: 15, isPersonal: true),
            IndexedWord(text: "仰泳", weight: 10, isPersonal: false),
            IndexedWord(text: "丙", weight: nil, isPersonal: true),
        ])
    }

    @Test func 权重相同时按文件和行的顺序() throws {
        // 主词库在前；个人词库里按行的顺序（不按字的先后）
        let main = try DictFile.parse(WubiFixtures.mainDict)
        let user = try Self.dict(Self.userTable, ["丙\twqiy\t20", "甲\twqiy\t15", "乙\twqiy\t15"])
        let hamster = try Self.dict("wubi86_jidian_user_hamster", ["丁\twqiy\t15"])
        let idx = WubiCodeIndex(main: main, imports: [
            (name: Self.userTable, file: user), (name: "wubi86_jidian_user_hamster", file: hamster),
        ])
        #expect(idx.words(for: "wqiy").map(\.text) == ["你", "丙", "甲", "乙", "丁", "仰泳"])
    }

    @Test func 放第一个前面() {
        #expect(Self.fixture.weight(forPosition: 0, code: "wqiy") == .weight(30))   // 你 20 + 10
    }

    @Test func 放中间() {
        #expect(Self.fixture.weight(forPosition: 1, code: "wqiy") == .weight(15))   // 你 20、仰泳 10 之间
    }

    @Test func 中间向下取整() throws {
        let idx = try Self.index(user: ["甲\tqqqq\t20", "乙\tqqqq\t17"])
        #expect(idx.weight(forPosition: 1, code: "qqqq") == .weight(18))
    }

    @Test func 放最后() {
        #expect(Self.fixture.weight(forPosition: 99, code: "wqiy") == .noWeight)
        #expect(Self.fixture.weight(forPosition: 2, code: "wqiy") == .noWeight)
    }

    @Test func 没有空档() throws {
        let idx = try Self.index(user: ["甲\tqqqq\t20", "乙\tqqqq\t19"])
        #expect(idx.weight(forPosition: 1, code: "qqqq") == .noRoom)
        // 前后都不碰别人的权重
        #expect(idx.weight(forPosition: 0, code: "qqqq") == .weight(30))
        #expect(idx.weight(forPosition: 2, code: "qqqq") == .noWeight)
    }

    @Test func 编码下还没有词() {
        #expect(Self.fixture.weight(forPosition: 0, code: "qqqq") == .noWeight)
        #expect(Self.fixture.words(for: "qqqq").isEmpty)
    }

    @Test func 全是不带权重的词() throws {
        let idx = try Self.index(user: ["甲\tqqqq", "乙\tqqqq"])
        #expect(idx.weight(forPosition: 0, code: "qqqq") == .weight(10))   // 0 + 10
        #expect(idx.weight(forPosition: 1, code: "qqqq") == .noRoom)
    }

    @Test func 带权重的词和不带权重的词之间() throws {
        // 不带权重算 0：仰泳 10 和 丙（无权重）之间 → 5
        let idx = try Self.index(user: ["丙\twqiy"])
        #expect(idx.weight(forPosition: 2, code: "wqiy") == .weight(5))
    }

    @Test func 负权重算0() throws {
        let idx = try Self.index(user: ["甲\tqqqq\t-5", "乙\tqqqq\t1", "丙\tqqqq"])
        #expect(idx.words(for: "qqqq").map(\.text) == ["乙", "甲", "丙"])
        #expect(idx.weight(forPosition: 1, code: "qqqq") == .noRoom)    // 1 和 0 之间
        let neg = try Self.index(user: ["甲\tqqqq\t-5"])
        #expect(neg.weight(forPosition: 0, code: "qqqq") == .weight(10))
    }

    @Test func 改位置时去掉自己() throws {
        // 甲 25 在你 20 前面；要挪到「你」和「仰泳」之间
        let idx = try Self.index(user: ["甲\twqiy\t25"])
        let me = DictEntry(text: "甲", code: "wqiy", weight: 25)
        #expect(idx.weight(forPosition: 1, code: "wqiy") == .weight(22))   // 不去掉自己：甲 25、你 20 之间
        #expect(idx.weight(forPosition: 1, code: "wqiy", excluding: me) == .weight(15))
        #expect(idx.weight(forPosition: 0, code: "wqiy", excluding: me) == .weight(30))
        #expect(idx.weight(forPosition: 2, code: "wqiy", excluding: me) == .noWeight)
    }

    @Test func 去掉自己只去个人词库里的那一条() throws {
        // 主词库里同编码的「你」不会被当成自己去掉
        let idx = try Self.index(user: [])
        let notMine = DictEntry(text: "你", code: "wqiy", weight: 20)
        #expect(idx.weight(forPosition: 1, code: "wqiy", excluding: notMine) == .weight(15))
    }

    @Test func 已经有了() throws {
        let idx = try Self.index(user: ["甲\twqiy\t100", "你\twqiy\t5"])
        #expect(idx.contains(text: "甲", code: "wqiy") == (inPersonal: true, inOthers: false))
        #expect(idx.contains(text: "仰泳", code: "wqiy") == (inPersonal: false, inOthers: true))
        #expect(idx.contains(text: "你", code: "wqiy") == (inPersonal: true, inOthers: true))
        #expect(idx.contains(text: "你", code: "wqbh") == (inPersonal: false, inOthers: false))
        #expect(idx.contains(text: "丁", code: "wqiy") == (inPersonal: false, inOthers: false))
    }

    @Test func 同词同码只算第一个() throws {
        // librime 编译时同一个词、同一个编码只留先读到的那条（主词库在前），个人词库里权重再大也没用
        let idx = try Self.index(user: ["仰泳\twqiy\t100"])
        #expect(idx.words(for: "wqiy") == [
            IndexedWord(text: "你", weight: 20, isPersonal: false),
            IndexedWord(text: "仰泳", weight: 10, isPersonal: false),
        ])
        #expect(idx.contains(text: "仰泳", code: "wqiy") == (inPersonal: true, inOthers: true))
    }

    @Test func 不带编码的词不进索引() throws {
        let idx = try Self.index(user: ["张三丰"])
        #expect(idx.words(for: "xddh").isEmpty)
    }

    @Test func 目标常量() {
        let t = WubiDictTarget.jidian
        #expect(t.packageID == "wubi86-jidian")
        #expect(t.mainDict == "wubi86_jidian.dict.yaml")
        #expect(t.userDict == "wubi86_jidian_user.dict.yaml")
        #expect(t.schemaPrefix == "wubi86_jidian")
        #expect(t.userTable == "wubi86_jidian_user")
    }

    // MARK: load

    @Test func 从包里读() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = try WubiFixtures.makePackage(in: dir.url)
        let idx = try WubiCodeIndex.load(from: pkg, personalUserDict: nil, target: .jidian)
        #expect(idx.words(for: "wqiy").map(\.text) == ["你", "仰泳"])
        // 包里的个人词库也算个人的
        #expect(idx.words(for: "wxyt") == [IndexedWord(text: "分组词条", weight: nil, isPersonal: true)])
    }

    @Test func 个人词库用给的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = try WubiFixtures.makePackage(in: dir.url)
        let personal = dir.url.appending(path: "personal.dict.yaml")
        try Data("---\nname: wubi86_jidian_user\n...\n甲\twqiy\t100\n".utf8).write(to: personal)
        let idx = try WubiCodeIndex.load(from: pkg, personalUserDict: personal, target: .jidian)
        #expect(idx.words(for: "wqiy").map(\.text) == ["甲", "你", "仰泳"])
        #expect(idx.words(for: "wxyt").isEmpty)   // 包里那份不读了
    }

    @Test func 导入表不往下读和缺失() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = try WubiFixtures.makePackage(in: dir.url)
        let files = pkg.filesDirectory
        // 主词库多列一个包里没有的表（跳过）；扩展词库自己再导入一个表（librime 不读它，见 WubiOrderCompileTests）
        let main = WubiFixtures.mainDict.replacingOccurrences(
            of: "  - wubi86_jidian_extra      # 扩展词库",
            with: "  - wubi86_jidian_extra      # 扩展词库\n  - wubi86_jidian_missing")
        try Data(main.utf8).write(to: files.appending(path: WubiFixtures.mainName))
        try Data("---\nname: wubi86_jidian_extra\nimport_tables:\n  - wubi86_jidian_more\n...\n戊\twqiy\t12\n".utf8)
            .write(to: files.appending(path: WubiFixtures.extraName))
        try Data("---\nname: wubi86_jidian_more\n...\n己\twqiy\t11\n".utf8)
            .write(to: files.appending(path: "wubi86_jidian_more.dict.yaml"))
        let idx = try WubiCodeIndex.load(from: pkg, personalUserDict: nil, target: .jidian)
        #expect(idx.words(for: "wqiy").map(\.text) == ["你", "戊", "仰泳"])
    }

    @Test func 没有主词库报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = try WubiFixtures.makePackage(in: dir.url)
        try FileManager.default.removeItem(at: pkg.filesDirectory.appending(path: WubiFixtures.mainName))
        #expect(throws: (any Error).self) {
            try WubiCodeIndex.load(from: pkg, personalUserDict: nil, target: .jidian)
        }
    }
}
