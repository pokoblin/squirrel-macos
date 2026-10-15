import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlGenerateTests {
    func context(_ dir: TempDir, catalog: Catalog) -> (Rimectl.Context, Output) {
        let output = Output(echo: false)
        let ctx = Rimectl.Context(http: FakeHTTPClient(), retry: .immediate, catalog: { catalog },
                                  defaultPaths: Fixtures.paths(dir), output: output)
        return (ctx, output)
    }

    @Test func settings_init写起步方案() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(dir, catalog: try Catalog.builtIn())
        #expect(await Rimectl.run(["settings", "init", "wubi-pinyin"], ctx) == 0)
        #expect(try SettingsStore(paths: Fixtures.paths(dir)).load() == Settings.starter(.wubiPinyin))
        #expect(await Rimectl.run(["settings", "init", "rime-ice"], ctx) == 1)
        #expect(out.text.contains("已经有设置了"))
        #expect(await Rimectl.run(["settings", "init", "rime-ice", "--force"], ctx) == 0)
        #expect(try SettingsStore(paths: Fixtures.paths(dir)).load()?.schemas == ["rime_ice"])
        #expect(await Rimectl.run(["settings", "init", "nope"], ctx) == 2)
    }

    @Test func settings_show打印设置() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(dir, catalog: try Catalog.builtIn())
        #expect(await Rimectl.run(["settings", "show"], ctx) == 1)
        #expect(out.text.contains("还没有设置"))
        try SettingsStore(paths: Fixtures.paths(dir)).save(.starter(.flypy))
        #expect(await Rimectl.run(["settings", "show"], ctx) == 0)
        #expect(out.text.contains("double_pinyin_flypy"))
    }

    @Test func generate用缓存生成到输出目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb", "py"]))
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        let target = dir.url.appending(path: "out")
        #expect(await Rimectl.run(["generate", "--cache-only", "--out", target.path], ctx) == 0)
        #expect(GenFixtures.exists(target, "default.custom.yaml"))
        #expect(GenFixtures.exists(target, "py_ext.dict.yaml"))
        #expect(out.text.contains("个文件"))
    }

    @Test func generate拒绝写真实的Rime目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb"]))
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        let real = NSHomeDirectory() + "/Library/Rime/squirrel-macos-should-not-exist"
        #expect(await Rimectl.run(["generate", "--cache-only", "--out", real], ctx) == 1)
        #expect(out.text.contains("拒绝"))
        #expect(!FileManager.default.fileExists(atPath: real))
    }

    @Test func generate没有设置() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        #expect(await Rimectl.run(["generate", "--out", dir.url.appending(path: "o").path], ctx) == 1)
        #expect(out.text.contains("还没有设置"))
    }

    @Test func generate输出目录不空() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb"]))
        let target = dir.url.appending(path: "out")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: target.appending(path: "a.txt"))
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        #expect(await Rimectl.run(["generate", "--cache-only", "--out", target.path], ctx) == 1)
        #expect(out.text.contains("输出目录不是空的"))
    }

    @Test func generate缺参数() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, _) = context(dir, catalog: try GenFixtures.catalog())
        #expect(await Rimectl.run(["generate"], ctx) == 2)
    }
}
