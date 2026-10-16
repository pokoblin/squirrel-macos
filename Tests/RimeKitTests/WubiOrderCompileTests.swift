import Foundation
import Testing
@testable import RimeKit

/// 用真的 librime 确认：同一编码下的顺序和 WubiCodeIndex 算的一样（需要装好鼠须管）
@Suite(.enabled(if: RimeTools.installed))
struct WubiOrderCompileTests {
    static let userHead = "---\nname: wubi86_jidian_user\nversion: \"test\"\nsort: original\ndict_grouped: true\n...\n"
    static let hamsterHead = "---\nname: wubi86_jidian_user_hamster\nversion: \"test\"\nsort: original\n...\n"

    /// 编译夹具（换掉个人词库和别的文件），打 code，翻完所有页，返回全部候选
    static func librimeOrder(_ code: String, userDict: String, extraFiles: [String: String] = [:],
                             in dir: URL) async throws -> [String] {
        let rime = try WubiFixtures.compiled(in: dir.appending(path: "rime"), userDict: userDict, extraFiles: extraFiles)
        let session = PreviewSession(helper: PreviewFixtures.helper)
        _ = try await session.open(userDir: rime, schema: "wubi86_jidian")
        _ = try await session.clear()
        var state = try await session.input(code)
        var out = state.candidates.map(\.text)
        var pages = 1
        while !state.isLastPage && pages < 20 {
            state = try await session.key(.pageDown)
            out += state.candidates.map(\.text)
            pages += 1
        }
        await session.close()
        return out
    }

    /// 同样的文件做成缓存包，个人词库用 personal 文件，读成索引
    static func index(userDict: String, extraFiles: [String: String] = [:], in dir: URL) throws -> WubiCodeIndex {
        let pkg = try WubiFixtures.makePackage(in: dir.appending(path: "cache"))
        for (name, text) in extraFiles {
            try Data(text.utf8).write(to: pkg.filesDirectory.appending(path: name))
        }
        let personal = dir.appending(path: "personal.dict.yaml")
        try Data(userDict.utf8).write(to: personal)
        return try WubiCodeIndex.load(from: pkg, personalUserDict: personal, target: .jidian)
    }

    @Test(.timeLimit(.minutes(1))) func 带权重的个人词库() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let user = Self.userHead + "甲\twqiy\t100\n乙\twqiy\t15\n丙\twqiy\n"
        let librime = try await Self.librimeOrder("wqiy", userDict: user, in: dir.url)
        let idx = try Self.index(userDict: user, in: dir.url)
        #expect(librime == ["甲", "你", "乙", "仰泳", "丙"])
        #expect(idx.words(for: "wqiy").map(\.text) == librime)
    }

    @Test(.timeLimit(.minutes(1))) func 权重相同() async throws {
        // 丙 和主词库的「你」都是 20；甲、乙同一文件同为 15（行的顺序和字的先后相反）；
        // 丁在 hamster 词库里也是 15（丁的编码点最小）
        let dir = try TempDir(); defer { dir.remove() }
        let user = Self.userHead + "丙\twqiy\t20\n甲\twqiy\t15\n乙\twqiy\t15\n"
        let extra = [WubiFixtures.hamsterName: Self.hamsterHead + "丁\twqiy\t15\n"]
        let librime = try await Self.librimeOrder("wqiy", userDict: user, extraFiles: extra, in: dir.url)
        let idx = try Self.index(userDict: user, extraFiles: extra, in: dir.url)
        #expect(librime == ["你", "丙", "甲", "乙", "丁", "仰泳"])
        #expect(idx.words(for: "wqiy").map(\.text) == librime)
    }

    @Test(.timeLimit(.minutes(1))) func 同词同码() async throws {
        // 个人词库里重复主词库已有的「仰泳 wqiy」，权重更大：只留主词库那条（还在你后面）
        let dir = try TempDir(); defer { dir.remove() }
        let user = Self.userHead + "仰泳\twqiy\t100\n"
        let librime = try await Self.librimeOrder("wqiy", userDict: user, in: dir.url)
        let idx = try Self.index(userDict: user, in: dir.url)
        #expect(librime == ["你", "仰泳"])
        #expect(idx.words(for: "wqiy").map(\.text) == librime)
    }

    @Test(.timeLimit(.minutes(1))) func 导入表里的导入表() async throws {
        // 扩展词库自己再导入一个表：librime 不往下读，只读主词库头部列的那几个表
        let dir = try TempDir(); defer { dir.remove() }
        let extra = [
            WubiFixtures.extraName: "---\nname: wubi86_jidian_extra\nversion: \"test\"\nimport_tables:\n  - wubi86_jidian_more\n...\n戊\twqiy\t12\n",
            "wubi86_jidian_more.dict.yaml": "---\nname: wubi86_jidian_more\nversion: \"test\"\n...\n己\twqiy\t11\n",
        ]
        let librime = try await Self.librimeOrder("wqiy", userDict: Self.userHead, extraFiles: extra, in: dir.url)
        let idx = try Self.index(userDict: Self.userHead, extraFiles: extra, in: dir.url)
        #expect(librime == ["你", "戊", "仰泳"])
        #expect(idx.words(for: "wqiy").map(\.text) == librime)
    }

    @Test(.timeLimit(.minutes(1))) func 缺失的导入表编译失败() async throws {
        // librime 遇到 import_tables 里列了却不存在的表，整个编译失败；索引那边跳过它不报错
        let dir = try TempDir(); defer { dir.remove() }
        let main = WubiFixtures.mainDict.replacingOccurrences(
            of: "  - wubi86_jidian_extra      # 扩展词库",
            with: "  - wubi86_jidian_extra      # 扩展词库\n  - wubi86_jidian_missing")
        #expect(throws: WubiFixtures.CompileFailed.self) {
            try WubiFixtures.compiled(in: dir.url.appending(path: "rime"), extraFiles: [WubiFixtures.mainName: main])
        }
    }

    @Test(.timeLimit(.minutes(1))) func 头部没有version的词库整个不算() async throws {
        // 编译照样成功，但这个词库里的词一个也打不出来
        let dir = try TempDir(); defer { dir.remove() }
        let user = "---\nname: wubi86_jidian_user\nsort: original\n...\n甲\twqiy\t100\n"
        let librime = try await Self.librimeOrder("wqiy", userDict: user, in: dir.url)
        #expect(librime == ["你", "仰泳"])
    }

    @Test(.timeLimit(.minutes(1))) func 不写权重和负权重都算0() async throws {
        // 甲 -5、丙 0、丁（不写）一样大，按行的顺序；乙 1 在它们前面
        let dir = try TempDir(); defer { dir.remove() }
        let user = Self.userHead + "甲\twqiy\t-5\n乙\twqiy\t1\n丙\twqiy\t0\n丁\twqiy\n"
        let librime = try await Self.librimeOrder("wqiy", userDict: user, in: dir.url)
        let idx = try Self.index(userDict: user, in: dir.url)
        #expect(librime == ["你", "仰泳", "乙", "甲", "丙", "丁"])
        #expect(idx.words(for: "wqiy").map(\.text) == librime)
    }
}
