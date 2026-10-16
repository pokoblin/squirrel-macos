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

    static let extraHead = "---\nname: wubi86_jidian_extra\nversion: \"test\"\nsort: by_weight\n...\n"

    /// 编译、打 wqiy，断言 librime 的顺序是 expected，索引算的也一样
    static func check(user: String, extra: String? = nil, expected: [String]) async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let files = extra.map { [WubiFixtures.extraName: Self.extraHead + $0] } ?? [:]
        let librime = try await librimeOrder("wqiy", userDict: userHead + user, extraFiles: files, in: dir.url)
        let idx = try index(userDict: userHead + user, extraFiles: files, in: dir.url)
        #expect(librime == expected)
        #expect(idx.words(for: "wqiy").map(\.text) == librime)
    }

    @Test(.timeLimit(.minutes(1))) func 导入表按列的顺序不按名字() async throws {
        // extra 在 import_tables 里排最后，按名字却排在 user 前面：同为 12 时个人词库的甲在前
        try await Self.check(user: "甲\twqiy\t12\n", extra: "戊\twqiy\t12\n",
                             expected: ["你", "甲", "戊", "仰泳"])
    }

    @Test(.timeLimit(.minutes(1))) func 权重0不写权重负权重一样大() async throws {
        // 三种写法换两种行的顺序，结果都跟着行走：说明 0、不写、-5 一样大
        try await Self.check(user: "丙\twqiy\t0\n乙\twqiy\n甲\twqiy\t-5\n",
                             expected: ["你", "仰泳", "丙", "乙", "甲"])
        try await Self.check(user: "甲\twqiy\t-5\n乙\twqiy\n丙\twqiy\t0\n",
                             expected: ["你", "仰泳", "甲", "乙", "丙"])
    }

    @Test(.timeLimit(.minutes(1))) func 负权重之间也一样大() async throws {
        // -100 在 -1 前面：负数不比大小，按行的顺序
        try await Self.check(user: "甲\twqiy\t-100\n乙\twqiy\t-1\n",
                             expected: ["你", "仰泳", "甲", "乙"])
    }

    @Test(.timeLimit(.minutes(1))) func 不写权重的个人词在扩展词库权重0的词前面() async throws {
        // 「放最后 = 不写权重」不一定真在最后：个人词库在 import_tables 里排在扩展词库前面
        try await Self.check(user: "甲\twqiy\n", extra: "戊\twqiy\t0\n",
                             expected: ["你", "仰泳", "甲", "戊"])
    }

    @Test(.timeLimit(.minutes(2))) func 按算出的权重放进去真的在那个位置() async throws {
        // 一个一个加：每次用索引算权重，写进个人词库，重新编译，看 librime 把它放在选的位置
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = try WubiFixtures.makePackage(in: dir.url.appending(path: "cache"))
        let personal = dir.url.appending(path: "personal.dict.yaml")
        var user = try DictFile.parse(Self.userHead)
        // 甲放第一个前面（30）；乙放你 20、仰泳 10 之间（15）；丙放甲 30、你 20 之间（25）
        for (step, (text, position, weight)) in [("甲", 0, 30), ("乙", 2, 15), ("丙", 1, 25)].enumerated() {
            try Data(user.render().utf8).write(to: personal)
            let idx = try WubiCodeIndex.load(from: pkg, personalUserDict: personal, target: .jidian)
            let choice = idx.weight(forPosition: position, code: "wqiy")
            #expect(choice == .weight(weight))
            guard case .weight(let w) = choice else { return }
            user.append(DictEntry(text: text, code: "wqiy", weight: w))
            let librime = try await Self.librimeOrder(
                "wqiy", userDict: user.render(), in: dir.url.appending(path: "step\(step)"))
            #expect(librime.firstIndex(of: text) == position, "\(text)：\(librime)")
        }
    }
}
