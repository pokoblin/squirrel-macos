import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTransferTests {
    typealias T = TransferFixtures

    struct CLI {
        let machine: T.Machine
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", machine.locations.rimeDirectory.path], context)
        }
    }

    func cli(_ m: T.Machine) -> CLI {
        let output = Output(echo: false)
        let catalog = m.catalog
        var context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: m.paths, output: output,
            locations: m.locations, compiler: FakeCompiler(), squirrel: m.squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in })
        context.userDBTool = m.tool
        context.textReplacementSnapshot = { TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0) }
        return CLI(machine: m, output: output, context: context)
    }

    @Test func 导出再导入到另一台() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let b = try T.machine(withSettings: false, userDB: [:], running: false); defer { b.dir.remove() }
        let file = b.dir.url.appending(path: "e.zip")
        let ca = cli(a)
        #expect(await ca.run(["export", file.path]) == 0)
        #expect(ca.output.text.contains("已导出"))
        #expect(ca.output.text.contains("输入习惯 1 份"))
        let cb = cli(b)
        #expect(await cb.run(["import", file.path, "--cache-only"]) == 0)
        #expect(cb.output.text.contains("部署完成"))
        #expect(cb.output.text.contains("已合并输入习惯：wb_py"))
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        #expect(try PersonalContent.load(from: b.paths).phrases == [T.phrase])
        #expect(b.tool.dbs["wb_py"] == T.snapshot)
    }

    @Test func 输出里没有个人内容() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        let c = cli(a)
        #expect(await c.run(["export", file.path]) == 0)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 0)
        for secret in ["私人短语", "私人词条", "你好"] {
            #expect(!c.output.text.contains(secret), "输出里有「\(secret)」")
        }
    }

    @Test func 不带输入习惯() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        let c = cli(a)
        #expect(await c.run(["export", file.path, "--no-userdb"]) == 0)
        #expect(a.tool.calls == [])
        #expect(a.squirrel.calls == [])
    }

    @Test func 已有文件要加force() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        try Data("旧".utf8).write(to: file)
        let c = cli(a)
        #expect(await c.run(["export", file.path]) == 1)
        #expect(c.output.text.contains("--force"))
        #expect(await c.run(["export", file.path, "--force"]) == 0)
    }

    @Test func 没有设置不能导出() async throws {
        let a = try T.machine(withSettings: false); defer { a.dir.remove() }
        let c = cli(a)
        #expect(await c.run(["export", a.dir.url.appending(path: "e.zip").path]) == 1)
        #expect(c.output.text.contains("还没有设置"))
    }

    @Test func 不是导出文件() async throws {
        let b = try T.machine(withSettings: false); defer { b.dir.remove() }
        let file = b.dir.url.appending(path: "x.zip")
        try Data("不是".utf8).write(to: file)
        let c = cli(b)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 1)
        #expect(c.output.text.contains("不是 squirrel-macos 的导出文件"))
    }

    @Test func 没装鼠须管时先装() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        #expect(await cli(a).run(["export", file.path]) == 0)
        try FileManager.default.removeItem(at: a.locations.squirrelApp)
        let c = cli(a)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 1)
        #expect(c.output.text.contains("rimectl install"))
    }

    @Test func 输入习惯合并不上时提示再运行一次() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        #expect(await cli(a).run(["export", file.path]) == 0)
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let locked = T.Machine(dir: b.dir, paths: b.paths, locations: b.locations, squirrel: b.squirrel,
                               tool: FakeUserDBTool(lockedFailures: 99), catalog: b.catalog, packages: b.packages)
        let c = cli(locked)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 1)
        #expect(c.output.text.contains("再运行一次 rimectl import"))
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
    }
}
