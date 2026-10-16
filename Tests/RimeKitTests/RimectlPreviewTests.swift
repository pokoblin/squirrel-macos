import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

/// rimectl preview：用编译好的临时配置跑真的 librime（需要宿主机装了鼠须管）
@Suite(.enabled(if: RimeTools.installed)) struct RimectlPreviewTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let rime: URL
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(["preview"] + args + ["--rime-dir", rime.path, "--data-dir", paths.root.path], context)
        }
    }

    func env() throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let rime = try PreviewFixtures.compiledConfig(in: dir.url)
        let output = Output(echo: false)
        let catalog = try GenFixtures.catalog()
        var context = Rimectl.Context(http: FakeHTTPClient(), retry: .immediate, catalog: { catalog },
                                      defaultPaths: paths, output: output)
        context.previewHelper = PreviewFixtures.helper
        return Env(dir: dir, paths: paths, rime: rime, output: output, context: context)
    }

    @Test func 每个编码一行() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["--schema", "py", "nihao", "yi"]) == 0)
        let lines = e.output.text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("nihao\t你好"))
        #expect(lines[1].hasPrefix("yi\t一"))
        #expect(lines[1].contains(" | "))
    }

    @Test func 列出方案() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["--list"]) == 0)
        let lines = e.output.text.split(separator: "\n").map(String.init)
        #expect(lines.contains { $0.hasPrefix("py\t") })
        #expect(lines.contains { $0.hasPrefix("wb\t") })
    }

    @Test func 找词() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["--schema", "py", "--find", "你好", "nihao"]) == 0)
        #expect(e.output.text.contains("找到：第 1 页第 1 个"))
    }

    @Test func 找词翻页后从1数() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["--schema", "py", "--find", "揖", "yi"]) == 0)
        #expect(e.output.text.contains("找到：第 2 页第 2 个"))
    }

    @Test func 没找到退出码1() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["--schema", "py", "--find", "不存在", "nihao"]) == 1)
        #expect(e.output.text.contains("没找到（最多翻了 5 页）"))
    }

    @Test func 没有这个方案() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["--schema", "nope", "nihao"]) == 1)
        #expect(e.output.text.contains("nope"))
    }

    @Test func 用完删掉副本() async throws {
        let e = try env(); defer { e.dir.remove() }
        _ = await e.run(["--schema", "py", "nihao"])
        _ = await e.run(["--schema", "nope", "nihao"])
        let left = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(left.isEmpty)
    }

    @Test func pending用已保存的设置和缓存() async throws {
        let e = try env(); defer { e.dir.remove() }
        _ = try GenFixtures.makePackages(in: e.paths.packages)
        try SettingsStore(paths: e.paths).save(Settings(schemas: ["py"]))
        #expect(await e.run(["--pending", "--schema", "py", "nihao"]) == 0)
        #expect(e.output.text.split(separator: "\n").first?.hasPrefix("nihao\t你好") == true)
    }

    @Test func 没带方案也没带list是用法错误() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run([]) == 2)
        #expect(await e.run(["--schema", "py"]) == 2)
        #expect(await e.run(["--schema", "py", "--find", "你好"]) == 2)
    }
}

/// 不需要鼠须管的
@Suite struct RimectlPreviewOfflineTests {
    @Test func 没部署过说清楚() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "rime", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
        let output = Output(echo: false)
        let catalog = try GenFixtures.catalog()
        var context = Rimectl.Context(http: FakeHTTPClient(), retry: .immediate, catalog: { catalog },
                                      defaultPaths: Fixtures.paths(dir), output: output)
        context.previewHelper = PreviewFixtures.helper
        let code = await Rimectl.run(["preview", "--list", "--rime-dir", rime.path], context)
        #expect(code == 1)
        #expect(output.text.contains("还没部署过"))
    }
}
