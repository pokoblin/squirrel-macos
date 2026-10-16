import Foundation
import Testing
@testable import RimeKit

/// 五笔个人词库编辑器在真的极点五笔包上的检查（计划细节 9）。要联网，要宿主机装了鼠须管：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineWubiDictTests
/// 包下载到临时目录（几个测试共用一份缓存，所以一个一个跑），生成、编译都在临时目录，不碰真实的 ~/Library/Rime。
/// 测试里加的词都是编的。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1" && RimeTools.installed),
       .serialized)
struct OnlineWubiDictTests {
    static let target = WubiDictTarget.jidian
    static let hamsterName = "wubi86_jidian_user_hamster.dict.yaml"

    /// 几个测试共用的下载缓存（固定在系统临时目录下，下次运行接着用，版本没变就不重新下载）
    static var cachePaths: AppPaths {
        AppPaths(root: FileManager.default.temporaryDirectory
            .appending(path: "rimekit-online-wubi-cache", directoryHint: .isDirectory))
    }

    struct Prepared {
        var settings: Settings
        var catalog: Catalog
        var packages: [String: CachedPackage]
        var wubi: CachedPackage { packages[OnlineWubiDictTests.target.packageID]! }
    }

    /// 「五笔 + 拼音混输」起步设置要的包（极点五笔和雾凇词库）
    static func prepare() async throws -> Prepared {
        let catalog = try Catalog.builtIn()
        let settings = Settings.starter(.wubiPinyin)
        let store = PackageStore(paths: cachePaths)
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) { packages[spec.id] = try await store.fetch(spec) }
        return Prepared(settings: settings, catalog: catalog, packages: packages)
    }

    /// 包里那份文件，末尾加上这些词条
    static func appended(_ name: String, in package: CachedPackage, _ entries: [DictEntry]) throws -> DictFile {
        var file = try DictFile.parse(data: Data(contentsOf: package.filesDirectory.appending(path: name)))
        for e in entries { file.append(e) }
        return file
    }

    /// 把个人词库（和 hamster 词库）放进 personal/dicts，按起步设置生成、编译，返回编译好的目录
    static func compile(_ p: Prepared, user: DictFile, hamster: DictFile? = nil, in dir: TempDir) throws -> (out: URL, status: Int32, stderr: String) {
        let dicts = dir.url.appending(path: "personal/dicts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dicts, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, file) in [(target.userDict, user)] + (hamster.map { [(hamsterName, $0)] } ?? []) {
            let url = dicts.appending(path: name)
            try Data(file.render().utf8).write(to: url)
            urls.append(url)
        }
        let out = dir.url.appending(path: "out", directoryHint: .isDirectory)
        let result = try ConfigGenerator().generate(
            GenerationInput(settings: p.settings, catalog: p.catalog, packages: p.packages,
                            personal: PersonalContent(dicts: urls, phrases: []), textReplacementPhrases: []),
            into: out)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let build = try RimeTools.build(out)
        return (out, build.status, build.stderr)
    }

    /// 打 code，最多看 pages 页，返回所有候选（自动上屏的字放第一个）
    static func candidates(_ code: String, pages: Int = 3, in session: PreviewSession) async throws -> [String] {
        _ = try await session.clear()
        var state = try await session.input(code)
        var out = state.committed.map { [$0] } ?? []
        out += state.candidates.map(\.text)
        var n = 1
        while !state.isLastPage && n < pages {
            state = try await session.key(.pageDown)
            out += state.candidates.map(\.text)
            n += 1
        }
        return out
    }

    /// 打印测量结果（swift test 的输出里能看到）
    static func note(_ s: String) { print("[测量] \(s)") }

    // MARK: 细节 9：自动编码和 Rime 自己算的一样

    @Test(.timeLimit(.minutes(10))) func 自动编码和Rime自己算的一样() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try await Self.prepare()
        let user0 = try DictFile.parse(data: Data(contentsOf: p.wubi.filesDirectory.appending(path: Self.target.userDict)))
        let editor0 = try WubiEditor(package: p.wubi, userFile: user0)
        let encoder = try #require(editor0.encoder)

        #expect(encoder.encode("张三丰") == .codes(["xddh"]))
        #expect(encoder.encode("宋氏") == .codes(["psqa"]))                // 二字词：宋 psu、氏 qav
        #expect(encoder.encode("中华人民共和国") == .codes(["kwwl"]))      // 长词，主词库里也是 kwwl
        #expect(encoder.encode("宋氏中华国") == .codes(["pqkl"]))          // 编的五字词，词库里没有
        // 2b：彧 有两个四码全码 akge、gkgy；戈 有 a、agnt、agny
        #expect(encoder.encode("彧张") == .codes(["akxt", "gkxt"]))
        #expect(encoder.encode("戈张") == .codes(["agxt"]))

        // 这些词不写编码放进个人词库，让 Rime 编译时自己算
        let words = ["张三丰", "宋氏", "中华人民共和国", "宋氏中华国", "彧张", "戈张"]
        let user = try Self.appended(Self.target.userDict, in: p.wubi, words.map { DictEntry(text: $0) })
        let built = try Self.compile(p, user: user, in: dir)
        try #require(built.status == 0, "\(built.stderr)")

        let session = PreviewSession(helper: PreviewFixtures.helper)
        _ = try await session.open(userDir: built.out, schema: "wubi86_jidian")
        for word in words.prefix(4) {
            guard case .codes(let codes) = encoder.encode(word) else { continue }
            let match = try await PreviewProbe.find(word, code: codes[0], in: session)
            #expect(match != nil, "\(word) \(codes[0]) 打不出来")
        }

        // 最长编码不止一个时，Rime 给每种组合各建一条：彧张 在 akxt、gkxt 下都有
        let akxt = try await Self.candidates("akxt", in: session)
        let gkxt = try await Self.candidates("gkxt", in: session)
        #expect(akxt.contains("彧张"), "\(akxt)")
        #expect(gkxt.contains("彧张"), "\(gkxt)")
        // 不是最长的编码也参与组词：戈 的一码 a 加上 张 组出 axt（三码），戈张 在 axt 下排在主词库的「芗」后面、
        // 补全的词前面。我们只用最长的编码，算出的只有 agxt
        let agxt = try await Self.candidates("agxt", in: session)
        let axt = try await Self.candidates("axt", in: session)
        await session.close()
        #expect(agxt.contains("戈张"), "\(agxt)")
        #expect(axt.prefix(2) == ["芗", "戈张"], "\(axt)")
        // 编辑器的索引里，没写编码的词只放在第一个编码下（细节见报告）
        let editor = try WubiEditor(package: p.wubi, userFile: user)
        Self.note("akxt：librime \(akxt)；索引 \(editor.index.words(for: "akxt").map(\.text))")
        Self.note("gkxt：librime \(gkxt)；索引 \(editor.index.words(for: "gkxt").map(\.text))")
        Self.note("axt：librime \(axt.prefix(4))；索引 \(editor.index.words(for: "axt").map(\.text))")
    }

    // MARK: 2a：没写编码的词和同码、同权重的有编码词谁在前

    @Test(.timeLimit(.minutes(10))) func 没写编码的词的位置() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try await Self.prepare()
        // 宋张（编的）自动编码 psxt。个人词库里先写它（不写编码），后面一行写同码的测甲；hamster 词库里有同码的测乙。
        // 都不写权重（都算 0）
        let user = try Self.appended(Self.target.userDict, in: p.wubi,
                                     [DictEntry(text: "宋张"), DictEntry(text: "测甲", code: "psxt")])
        let hamster = try Self.appended(Self.hamsterName, in: p.wubi, [DictEntry(text: "测乙", code: "psxt")])
        let built = try Self.compile(p, user: user, hamster: hamster, in: dir)
        try #require(built.status == 0, "\(built.stderr)")

        let session = PreviewSession(helper: PreviewFixtures.helper)
        _ = try await session.open(userDir: built.out, schema: "wubi86_jidian")
        let librime = try await Self.candidates("psxt", in: session)
        await session.close()

        // 索引：编辑器补上自动编码的个人词库，hamster 换成上面那份
        let editor = try WubiEditor(package: p.wubi, userFile: user)
        let tables = try WubiCodeIndex.loadTables(from: p.wubi, target: Self.target)
        let imports = tables.imports.map { t -> (name: String, entries: [DictEntry]) in
            if t.name == Self.target.userTable { return (t.name, editor.entriesWithCodes) }
            if t.name + ".dict.yaml" == Self.hamsterName { return (t.name, hamster.entries) }
            return (t.name, t.file.entries)
        }
        let index = WubiCodeIndex(main: tables.main.entries, imports: imports)
        let indexed = index.words(for: "psxt").map(\.text)
        Self.note("psxt librime：\(librime)；索引 \(indexed)")
        // librime：权重一样时，没写编码的词排在所有写了编码的词后面——连后面 hamster 词库里的测乙也在它前面
        #expect(librime == ["测甲", "测乙", "宋张"])
        // 索引按行的顺序把它排在最前，和 librime 不一样。应用写进去的词都带编码，只影响用户手写的无编码词
        withKnownIssue("索引把没写编码的个人词按行的顺序排，librime 把它排在同权重的有编码词后面") {
            #expect(indexed == librime)
        }
    }

    // MARK: 2c：简入繁出、混输里的检查，短编码

    @Test(.timeLimit(.minutes(10))) func 简入繁出和混输里的检查() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try await Self.prepare()
        let user = try Self.appended(Self.target.userDict, in: p.wubi,
                                     [DictEntry(text: "张三丰"), DictEntry(text: "宋氏", code: "psqa")])
        let built = try Self.compile(p, user: user, in: dir)
        try #require(built.status == 0, "\(built.stderr)")
        let editor = try WubiEditor(package: p.wubi, userFile: user)
        let entries = editor.entriesWithCodes.filter { ["张三丰", "宋氏"].contains($0.text) }

        for schema in ["wubi86_jidian", "wubi86_jidian_pinyin", "wubi86_jidian_trad"] {
            let session = PreviewSession(helper: PreviewFixtures.helper)
            let results = try await WubiCheck.run(entries, index: editor.index, engine: session,
                                                  userDir: built.out, schema: schema)
            Self.note("\(schema) 检查：\(zip(entries.map(\.text), results).map { "\($0) \($1)" })")
            if schema == "wubi86_jidian_trad" {
                // 简入繁出：候选是转换后的字（张三丰 → 張三丰），按原词找不到，报「打不出来」；繁简同形的宋氏照样找得到
                #expect(results == [.missing, .asExpected(page: 0, index: 0)])
            } else {
                #expect(results == [.asExpected(page: 0, index: 1), .asExpected(page: 0, index: 0)])
            }
            _ = try await session.open(userDir: built.out, schema: schema)
            for code in ["wq", "xd", "qnn", "ugd", "xddh"] {
                let exact = editor.index.words(for: code).map(\.text)
                let got = try await Self.candidates(code, pages: 2, in: session)
                Self.note("\(schema) \(code)：精确 \(exact)；librime \(got.prefix(exact.count + 3))")
                // 编码完全一样的五笔字词排最前，顺序和索引一样；后面才是补全的词、拼音的词（简入繁出是转换后的字，只比个数）
                #expect(!exact.isEmpty)
                if schema == "wubi86_jidian_trad" {
                    #expect(got.count >= exact.count)
                } else {
                    #expect(Array(got.prefix(exact.count)) == exact, "\(schema) \(code)：\(got)")
                }
            }
            await session.close()
        }
    }

    // MARK: 2d：真词库上的耗时（debug 编译）

    @Test(.timeLimit(.minutes(10))) func 真词库上的耗时() async throws {
        let p = try await Self.prepare()
        let user0 = try DictFile.parse(data: Data(contentsOf: p.wubi.filesDirectory.appending(path: Self.target.userDict)))
        let clock = ContinuousClock()
        var editor: WubiEditor?
        let initTime = try clock.measure { editor = try WubiEditor(package: p.wubi, userFile: user0) }
        let e = try #require(editor)
        // 编一个 5000 条的个人词库（两个常用字随便拼，编码自动算；一半不写编码）
        let chars = Array("的一是了我不人在他有这个上们来到时大地为子中你说生国年着就那和要她出也得里后自以会家可下而过天去能对小多然于心学么之都好看起发当没成只如事把还用第样道想作种开美总从无情己面最女但现前些所同日手又行意动方期它头经长儿回位分爱老因很给名法间斯知世什两次使身者被高已亲其进此话常与活正感")
        var big = user0
        var n = 0
        outer: for a in chars {
            for b in chars where a != b {
                let text = String([a, b])
                big.append(n % 2 == 0 ? DictEntry(text: text) : DictEntry(text: text, code: e.autoCode(text)))
                n += 1
                if n >= 5000 { break outer }
            }
        }
        let replaceSmall = clock.measure { _ = e.replacing(userFile: user0) }
        let replaceBig = clock.measure { _ = e.replacing(userFile: big) }
        var bigEditor: WubiEditor?
        let initBig = try clock.measure { bigEditor = try WubiEditor(package: p.wubi, userFile: big) }
        let appendOne = clock.measure { _ = bigEditor?.applying([DictEntry(text: "测试", code: "imyn")]) }
        Self.note("个人词库 \(user0.entries.count) 条 / \(big.entries.count) 条")
        Self.note("init（包里的个人词库）\(initTime)；init（5000 条）\(initBig)")
        Self.note("replacing（包里的个人词库）\(replaceSmall)；replacing（5000 条）\(replaceBig)；applying 一条（5000 条上）\(appendOne)")
        // 只防明显变慢（比如又变成随条数平方增长）；实测都在 0.2 秒以内
        for d in [initTime, initBig, replaceSmall, replaceBig, appendOne] { #expect(d < .seconds(5)) }
    }

    // MARK: Rime 算不出编码的无编码词

    /// rime_deployer 只记一条 E 日志、丢掉这个词，退出码 0，词库照样编出来、别的词照样能打。
    /// 应用编译时（DeployerCompiler）看到 E 行就算失败，所以在应用里会报编译失败
    @Test(.timeLimit(.minutes(10))) func 算不出编码的无编码词() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try await Self.prepare()
        // ☃ 不在主词库里，Rime 编不出码
        let user = try Self.appended(Self.target.userDict, in: p.wubi, [DictEntry(text: "测☃"), DictEntry(text: "测乙", code: "psxt")])
        let built = try Self.compile(p, user: user, in: dir)
        let errors = RimeLog.errorLines(built.stderr)
        Self.note("无编码的「测☃」：rime_deployer 退出码 \(built.status)；E 行 \(errors)")
        #expect(built.status == 0)
        #expect(errors.contains { $0.contains("Encode failure") })
        #expect(FileManager.default.fileExists(atPath: built.out.appending(path: "build/wubi86_jidian.table.bin").path))
        let session = PreviewSession(helper: PreviewFixtures.helper)
        _ = try await session.open(userDir: built.out, schema: "wubi86_jidian")
        let wq = try await Self.candidates("wq", pages: 1, in: session)
        let psxt = try await Self.candidates("psxt", pages: 1, in: session)
        await session.close()
        #expect(wq.first == "你")
        #expect(psxt == ["测乙"])
    }
}
