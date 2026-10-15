import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTakeoverTests {
    typealias F = TakeoverFixtures

    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", locations.rimeDirectory.path], context)
        }
    }

    func env(sample: Bool = true) throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let packages = try GenFixtures.makePackages(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        if sample { try F.wubiSample(packages, into: locations.rimeDirectory) }
        let output = Output(echo: false)
        let catalog = try GenFixtures.catalog()
        var context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: paths, output: output,
            locations: locations, compiler: FakeCompiler(), squirrel: FakeSquirrel(locations: locations, running: true),
            deployTimeout: .milliseconds(20), sleep: { _ in })
        context.textReplacements = { [F.fromTR] }
        return Env(dir: dir, paths: paths, locations: locations, output: output, context: context)
    }

    @Test func 预览不改任何东西() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        let text = e.output.text
        #expect(text.contains("五笔拼音（wb_py）"))
        #expect(text.contains("个人词库：2 个"))
        #expect(text.contains("手动短语：1 条"))
        #expect(text.contains("和 macOS 文本替换一样的短语：1 条"))
        #expect(text.contains("原样保留：notes.txt、weasel.custom.yaml"))
        #expect(text.contains("这只是预览"))
        #expect(!FileManager.default.fileExists(atPath: e.paths.settingsFile.path))
        #expect(try Ledger.load(e.paths).entries.isEmpty)
    }

    @Test func 输出里没有个人内容() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        for secret in ["私人短语", "替换短语", "私人词条", "私人五笔词"] {
            #expect(!e.output.text.contains(secret), "输出里有「\(secret)」")
        }
    }

    @Test func 确认接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["takeover", "--confirm", "--cache-only"]) == 0)
        #expect(e.output.text.contains("永久保留"))
        #expect(e.output.text.contains("部署完成"))
        #expect(try SettingsStore(paths: e.paths).load()?.schemas == ["wb_py", "wb"])
    }

    struct Unreadable: Error, CustomStringConvertible { var description: String { "数据库打不开" } }

    @Test func 读不了文本替换时只预览不接管() async throws {
        // 读不到就分不出哪些是文本替换的短语：接管会把它们存成手动短语（以后还会被导出）
        var e = try env(); defer { e.dir.remove() }
        var context = e.context
        context.textReplacements = { throw Unreadable() }
        e = Env(dir: e.dir, paths: e.paths, locations: e.locations, output: e.output, context: context)
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        #expect(e.output.text.contains("数据库打不开"))
        #expect(await e.run(["takeover", "--confirm", "--cache-only"]) == 1)
        #expect(e.output.text.contains("没有接管"))
        #expect(!FileManager.default.fileExists(atPath: e.paths.settingsFile.path))
        #expect(try Ledger.load(e.paths).entries.isEmpty)
    }

    @Test func 已经有设置时要加force() async throws {
        let e = try env(); defer { e.dir.remove() }
        try SettingsStore(paths: e.paths).save(Settings(schemas: ["wb"]))
        #expect(await e.run(["takeover", "--cache-only"]) == 1)
        #expect(e.output.text.contains("--force"))
        #expect(await e.run(["takeover", "--cache-only", "--force"]) == 0)
    }

    @Test func 已经由应用管理时不接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(e.paths)
        #expect(await e.run(["takeover", "--cache-only"]) == 1)
        #expect(e.output.text.contains("不用再接管"))
    }

    @Test func 空目录不用接管() async throws {
        let e = try env(sample: false); defer { e.dir.remove() }
        try F.put("var: {}\n", "user.yaml", in: e.locations.rimeDirectory)
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        #expect(e.output.text.contains("不用接管"))
    }

    @Test func 认不出方案() async throws {
        let e = try env(sample: false); defer { e.dir.remove() }
        try F.put("随手记\n", "notes.txt", in: e.locations.rimeDirectory)
        #expect(await e.run(["takeover", "--cache-only"]) == 1)
        #expect(e.output.text.contains("认不出来"))
    }

    @Test func 打开了文本替换同步时应用会带上文本替换() async throws {
        let e = try env(sample: false); defer { e.dir.remove() }
        var settings = Settings(schemas: ["wb"])
        settings.textReplacement.sync = true
        try SettingsStore(paths: e.paths).save(settings)
        #expect(await e.run(["apply", "--cache-only"]) == 0)
        let phrases = try String(contentsOf: e.locations.rimeDirectory.appending(path: "custom_phrase.txt"), encoding: .utf8)
        #expect(phrases.contains(F.fromTR.line))
    }
}
