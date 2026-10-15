import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlApplyTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let squirrel: FakeSquirrel
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", locations.rimeDirectory.path], context)
        }
    }

    func env() throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb", "py"]))
        let locations = try DeployFixtures.locations(dir)
        let squirrel = FakeSquirrel(locations: locations, running: true)
        let output = Output(echo: false)
        let catalog = try GenFixtures.catalog()
        let context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: paths, output: output,
            locations: locations, compiler: FakeCompiler(), squirrel: squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in })
        return Env(dir: dir, paths: paths, locations: locations, squirrel: squirrel, output: output, context: context)
    }

    @Test func apply成功() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["apply", "--cache-only"]) == 0)
        #expect(e.output.text.contains("已备份"))
        #expect(e.output.text.contains("部署完成"))
        #expect(FileManager.default.fileExists(atPath: e.locations.rimeDirectory.appending(path: "default.custom.yaml").path))
    }

    @Test func apply遇到外部改动() async throws {
        let e = try env(); defer { e.dir.remove() }
        try FileManager.default.createDirectory(at: e.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: e.locations.rimeDirectory.appending(path: "default.custom.yaml"))
        #expect(await e.run(["apply", "--cache-only"]) == 1)
        #expect(e.output.text.contains("default.custom.yaml：不是应用写的，这次会被覆盖"))
        #expect(e.output.text.contains("--overwrite"))
        #expect(await e.run(["apply", "--cache-only", "--overwrite"]) == 0)
    }

    @Test func apply部署有错误时退出码是1() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.squirrel.errorLine = "E20261015 14:07:26.215036 0x1 deployment_tasks.cc:376] dictionary 'wb' failed to compile."
        #expect(await e.run(["apply", "--cache-only"]) == 1)
        #expect(e.output.text.contains("词库 wb 编译失败"))
        #expect(e.output.text.contains("rimectl restore"))
    }

    @Test func status和restore() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["apply", "--cache-only"]) == 0)
        #expect(await e.run(["status"]) == 0)
        #expect(e.output.text.contains("鼠须管：已安装，正在运行"))
        #expect(e.output.text.contains("应用管理的文件："))
        #expect(await e.run(["restore", "--list"]) == 0)
        let id = try #require(BackupStore(paths: e.paths).list().first?.id)
        #expect(e.output.text.contains(id))
        #expect(await e.run(["restore", id]) == 0)
        #expect(e.output.text.contains("已还原到 \(id)"))
        #expect(await e.run(["restore", "nope"]) == 1)
        #expect(await e.run(["restore"]) == 2)
    }

    @Test func settings_set改设置() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["settings", "set", "font-point", "24"]) == 0)
        #expect(await e.run(["settings", "set", "layout", "linear"]) == 0)
        #expect(await e.run(["settings", "set", "schemas", "py,wb"]) == 0)
        #expect(await e.run(["settings", "set", "option", "wubi.pinyinDictionary=builtin"]) == 0)
        var s = try #require(try SettingsStore(paths: e.paths).load())
        #expect(s.appearance.fontPoint == 24)
        #expect(s.appearance.candidateListLayout == .linear)
        #expect(s.schemas == ["py", "wb"])
        #expect(s.options["wubi"]?["pinyinDictionary"] == "builtin")
        #expect(await e.run(["settings", "set", "font-point", "-"]) == 0)
        s = try #require(try SettingsStore(paths: e.paths).load())
        #expect(s.appearance.fontPoint == nil)
        #expect(await e.run(["settings", "set", "font-point", "999"]) == 1)
        #expect(e.output.text.contains("候选字字号是 999"))
        #expect(await e.run(["settings", "set", "nope", "1"]) == 2)
    }
}
