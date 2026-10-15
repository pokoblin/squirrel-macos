import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployerTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let squirrel: FakeSquirrel
        let packages: [String: CachedPackage]
        var rime: URL { locations.rimeDirectory }

        func deployer(compiler: FakeCompiler = FakeCompiler()) -> Deployer {
            Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                     watcher: DeployFixtures.watcher(locations), now: { Date(timeIntervalSince1970: 1_000) })
        }

        func input(_ settings: Settings) throws -> GenerationInput {
            try GenFixtures.input(settings, packages: packages, personal: try PersonalContent.load(from: paths))
        }

        func write(_ path: String, _ text: String) throws {
            let url = rime.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func read(_ path: String) throws -> String {
            try String(contentsOf: rime.appending(path: path), encoding: .utf8)
        }
    }

    func env(running: Bool = false) throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let locations = try DeployFixtures.locations(dir)
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        return Env(dir: dir, paths: paths, locations: locations,
                   squirrel: FakeSquirrel(locations: locations, running: running), packages: packages)
    }

    func applied(_ outcome: ApplyOutcome) throws -> ApplyReport {
        guard case .applied(let report) = outcome else {
            Issue.record("应该写入成功，实际是 \(outcome)")
            throw CancellationError()
        }
        return report
    }

    @Test func 第一次应用到空目录() async throws {
        let e = try env(); defer { e.dir.remove() }
        let report = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"]))))
        #expect(report.written.contains("default.custom.yaml"))
        #expect(report.written.contains("wb.schema.yaml"))
        #expect(report.removed.isEmpty)
        #expect(report.launched)
        #expect(e.squirrel.calls == ["launch"])
        #expect(report.deploy == DeployOutcome(finished: true, errors: []))
        #expect(report.backup.reason == "第一次应用前")
        #expect(!report.backup.permanent)   // 原来是空的，不用永久保留
        let ledger = try Ledger.load(e.paths)
        #expect(Set(ledger.entries.keys) == Set(report.written))
        #expect(ledger.entries["wb.dict.yaml"]?.origin == "package:wubi")
        #expect(ledger.appliedAt == Date(timeIntervalSince1970: 1_000))
        #expect(try e.read("default.custom.yaml").hasPrefix(Patch.header))
        let staging = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(staging.isEmpty)
    }

    @Test func 要覆盖应用不管的文件时先列出来什么都不写() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "mine")
        try e.write("my_notes.txt", "notes")
        let outcome = try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])))
        #expect(outcome == .externalChanges([.unmanaged("default.custom.yaml")]))
        #expect(try RimeFiles.configFiles(in: e.rime) == ["default.custom.yaml", "my_notes.txt"])
        #expect(try e.read("default.custom.yaml") == "mine")
        #expect(BackupStore(paths: e.paths).list().isEmpty)
        #expect(e.squirrel.calls.isEmpty)
    }

    @Test func 让覆盖时先永久备份再写不认识的文件不动() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "mine")
        try e.write("my_notes.txt", "notes")
        let report = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])),
                                                              options: ApplyOptions(overwriteExternalChanges: true)))
        #expect(report.backup.permanent)
        #expect(report.backup.files == ["default.custom.yaml", "my_notes.txt"])
        #expect(try e.read("my_notes.txt") == "notes")
        #expect(try e.read("default.custom.yaml").hasPrefix(Patch.header))
    }

    @Test func 应用管理的文件被外部改过或删了() async throws {
        let e = try env(); defer { e.dir.remove() }
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"]))))
        try e.write("default.custom.yaml", "hand edited")
        try FileManager.default.removeItem(at: e.rime.appending(path: "py.dict.yaml"))
        let outcome = try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"])))
        #expect(outcome == .externalChanges([.modified("default.custom.yaml"), .deleted("py.dict.yaml")]))
        #expect(try e.read("default.custom.yaml") == "hand edited")
    }

    @Test func 采用个人词库的外部修改() async throws {
        let e = try env(); defer { e.dir.remove() }
        try FileManager.default.createDirectory(at: e.paths.personalDicts, withIntermediateDirectories: true)
        try Data(GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"]).utf8).write(to: e.paths.personalDicts.appending(path: "py_user.dict.yaml"))
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"]))))
        let edited = GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1", "海豚\thai tun\t1"])
        try e.write("py_user.dict.yaml", edited)
        #expect(try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"])))
                == .externalChanges([.modified("py_user.dict.yaml")]))
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"])),
                                                     options: ApplyOptions(adoptPersonalChanges: true)))
        #expect(try String(contentsOf: e.paths.personalDicts.appending(path: "py_user.dict.yaml"), encoding: .utf8) == edited)
        #expect(try e.read("py_user.dict.yaml") == edited)
        #expect(try Ledger.load(e.paths).externalChanges(in: e.rime).isEmpty)
    }

    @Test func 编译失败时什么都不写() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("my_notes.txt", "notes")
        let compiler = FakeCompiler(report: CompileReport(succeeded: false, errors: [
            "E20261015 14:07:26.215025 0x1 dict_compiler.cc:115] neither nope.dict.yaml nor nope.table.bin exists.",
        ]))
        let outcome = try await e.deployer(compiler: compiler).apply(try e.input(Settings(schemas: ["wb"])))
        #expect(outcome == .compileFailed(["找不到词库 nope（缺少 nope.dict.yaml）"]))
        #expect(try RimeFiles.configFiles(in: e.rime) == ["my_notes.txt"])
        #expect(BackupStore(paths: e.paths).list().isEmpty)
        #expect(try Ledger.load(e.paths) == Ledger())
    }

    @Test func 第二次只写变了的删掉不再需要的() async throws {
        let e = try env(running: true); defer { e.dir.remove() }
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"]))))
        var settings = Settings(schemas: ["wb"])
        settings.appearance.fontPoint = 24
        let report = try applied(try await e.deployer().apply(try e.input(settings)))
        #expect(report.removed.contains("py.schema.yaml"))
        #expect(!FileManager.default.fileExists(atPath: e.rime.appending(path: "py.schema.yaml").path))
        #expect(report.written.contains("squirrel.custom.yaml"))
        #expect(!report.written.contains("wb.dict.yaml"))
        #expect(report.unchanged > 0)
        #expect(report.backup.reason == "应用改动前")
        #expect(e.squirrel.calls == ["reload", "reload"])
        #expect(!report.launched)
    }

    @Test func 写到一半失败自动还原() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("keep.txt", "keep")
        // 有一个和要写的文件同名的空目录，rename 会失败
        try FileManager.default.createDirectory(at: e.rime.appending(path: "wb.dict.yaml"), withIntermediateDirectories: true)
        let error = await #expect(throws: ApplyError.self) {
            try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])), options: ApplyOptions(overwriteExternalChanges: true))
        }
        guard case .writeFailed(_, let restored, _) = error else {
            Issue.record("应该是 writeFailed，实际是 \(String(describing: error))")
            return
        }
        #expect(restored)
        #expect(try RimeFiles.configFiles(in: e.rime) == ["keep.txt"])
        #expect(try Ledger.load(e.paths) == Ledger())
        #expect(e.squirrel.calls.isEmpty)
    }

    @Test func 部署日志有错误时报告出来() async throws {
        let e = try env(running: true); defer { e.dir.remove() }
        e.squirrel.errorLine = "E20261015 14:07:26.231144 0x1 deployment_tasks.cc:338] invalid schema definition in '/x/wb.schema.yaml'."
        let report = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb"]))))
        #expect(report.deploy == DeployOutcome(finished: true, errors: ["方案文件 wb.schema.yaml 的内容不对"]))
    }

    @Test func 同时应用时后来的被挡住() async throws {
        let e = try env(); defer { e.dir.remove() }
        let held = try ApplyLock.acquire(e.paths)
        await #expect(throws: ApplyError.busy) {
            try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])))
        }
        _ = held
    }

    @Test func 没装鼠须管() async throws {
        let e = try env(); defer { e.dir.remove() }
        var locations = e.locations
        locations.squirrelApp = e.dir.url.appending(path: "NoSuch.app")
        let deployer = Deployer(paths: e.paths, locations: locations, compiler: FakeCompiler(), squirrel: e.squirrel,
                                watcher: DeployFixtures.watcher(locations))
        await #expect(throws: ApplyError.squirrelNotInstalled) {
            try await deployer.apply(try e.input(Settings(schemas: ["wb"])))
        }
    }

    @Test func 可以要求这次的备份永久保留() async throws {
        let m = try TransferFixtures.machine(); defer { m.dir.remove() }
        try FileManager.default.createDirectory(at: m.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("随手记\n".utf8).write(to: m.locations.rimeDirectory.appending(path: "notes.txt"))
        let input = GenerationInput(settings: TransferFixtures.settings, catalog: m.catalog, packages: m.packages,
                                    personal: .empty, textReplacementPhrases: [])
        guard case .applied(let first) = try await m.deployer().apply(input) else { Issue.record("没有写入"); return }
        #expect(first.backup.permanent)   // 第一次应用前：本来就永久保留
        guard case .applied(let second) = try await m.deployer().apply(input, options: ApplyOptions(permanentBackupReason: "导入前")) else {
            Issue.record("没有写入"); return
        }
        #expect(second.backup.permanent)
        #expect(second.backup.reason == "导入前")
        guard case .applied(let third) = try await m.deployer().apply(input) else { Issue.record("没有写入"); return }
        #expect(!third.backup.permanent)
    }
}
