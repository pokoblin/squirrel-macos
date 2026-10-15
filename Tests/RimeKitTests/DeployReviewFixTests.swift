import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployReviewFixTests {
    @Test func 已经有永久备份时不再加新的永久备份() async throws {
        let e = try DeployerTests().env(running: true); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "mine")
        let overwrite = ApplyOptions(overwriteExternalChanges: true)
        guard case .applied(let first) = try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])), options: overwrite) else {
            Issue.record("第一次应该写入成功"); return
        }
        #expect(first.backup.permanent)
        _ = try await e.deployer().restore(first.backup.id)
        guard case .applied(let again) = try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])), options: overwrite) else {
            Issue.record("第二次应该写入成功"); return
        }
        #expect(again.backup.reason == "第一次应用前")
        #expect(!again.backup.permanent)
        #expect(BackupStore(paths: e.paths).list().filter(\.permanent).count == 1)
    }

    @Test func 还有别的外部改动时不动个人词库正本() async throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        let original = GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"])
        try FileManager.default.createDirectory(at: e.paths.personalDicts, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: e.paths.personalDicts.appending(path: "py_user.dict.yaml"))
        guard case .applied = try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"]))) else {
            Issue.record("第一次应该写入成功"); return
        }
        try e.write("py_user.dict.yaml", GenFixtures.dict("py_user", ["海豚\thai tun\t1"]))
        try e.write("default.custom.yaml", "hand edited")
        let outcome = try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"])),
                                                   options: ApplyOptions(adoptPersonalChanges: true))
        #expect(outcome == .externalChanges([.modified("default.custom.yaml")]))
        #expect(try String(contentsOf: e.paths.personalDicts.appending(path: "py_user.dict.yaml"), encoding: .utf8) == original)
    }

    @Test func 编译失败时也不动个人词库正本() async throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        let original = GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"])
        try FileManager.default.createDirectory(at: e.paths.personalDicts, withIntermediateDirectories: true)
        try Data(original.utf8).write(to: e.paths.personalDicts.appending(path: "py_user.dict.yaml"))
        guard case .applied = try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"]))) else {
            Issue.record("第一次应该写入成功"); return
        }
        try e.write("py_user.dict.yaml", GenFixtures.dict("py_user", ["海豚\thai tun\t1"]))
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 00:00:00.000000 0x1 a.cc:1] boom"]))
        let outcome = try await e.deployer(compiler: failing).apply(try e.input(Settings(schemas: ["wpy"])),
                                                                     options: ApplyOptions(adoptPersonalChanges: true))
        #expect(outcome == .compileFailed(["Rime 报错：boom"]))
        #expect(try String(contentsOf: e.paths.personalDicts.appending(path: "py_user.dict.yaml"), encoding: .utf8) == original)
    }

    @Test func git目录不算配置文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fm = FileManager.default
        for path in [".git/config", ".git/objects/ab/cd", "rime_ice.schema.yaml"] {
            let url = dir.url.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        #expect(try RimeFiles.configFiles(in: dir.url) == ["rime_ice.schema.yaml"])
    }
}
