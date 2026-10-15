import Foundation
import Testing
@testable import RimeKit

@Suite struct ImporterTests {
    typealias T = TransferFixtures

    /// 在 A 上导出，在 B 上打开
    func archive(for b: T.Machine) async throws -> ImportArchive {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = b.dir.url.appending(path: "from-a.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        return try ImportArchive.open(file, catalog: b.catalog, into: b.dir.url.appending(path: "import", directoryHint: .isDirectory))
    }

    func importer(_ b: T.Machine, _ compiler: FakeCompiler = FakeCompiler()) -> Importer {
        Importer(deployer: b.deployer(compiler), userDB: b.userDB, now: { T.date })
    }

    @Test func 导入到空的新电脑() async throws {
        let b = try T.machine(withSettings: false, userDB: [:], running: false); defer { b.dir.remove() }
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied = report.outcome else { Issue.record("没有写入：\(report.outcome)"); return }
        #expect(report.previous == nil)
        #expect(report.mergedUserDB == ["wb_py"])
        #expect(report.userDBError == nil)
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        let personal = try PersonalContent.load(from: b.paths)
        #expect(personal.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(personal.phrases == [T.phrase])
        #expect(b.tool.dbs["wb_py"] == T.snapshot)
        #expect(b.squirrel.calls.last == "launch")
        #expect(FileManager.default.fileExists(atPath: b.locations.rimeDirectory.appending(path: "wb_py.schema.yaml").path))
    }

    @Test func 原来有设置时先另存一份() async throws {
        let b = try T.machine(); defer { b.dir.remove() }
        try SettingsStore(paths: b.paths).save(Settings(schemas: ["py"]))
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        let previous = try #require(report.previous)
        #expect(previous.deletingLastPathComponent().standardizedFileURL.path == b.paths.beforeImport.standardizedFileURL.path)
        let old = try ImportArchive.open(previous, catalog: b.catalog, into: b.dir.url.appending(path: "old", directoryHint: .isDirectory))
        #expect(old.manifest.settings.schemas == ["py"])
        #expect(old.manifest.userDB == [])
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
    }

    @Test func 导入出错时告诉用户原来的设置另存在哪里() async throws {
        let b = try T.machine(); defer { b.dir.remove() }
        let a = try await archive(for: b)
        try FileManager.default.removeItem(at: a.personalDicts[0])   // 生成时复制个人词库会失败
        do {
            _ = try await importer(b).run(a, catalog: b.catalog, packages: b.packages, textReplacement: [])
            Issue.record("应该报错")
        } catch let TransferError.importFailed(_, previous) {
            #expect(FileManager.default.fileExists(atPath: previous))
            #expect(previous.hasPrefix(b.paths.beforeImport.path))
        }
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        #expect(try PersonalContent.load(from: b.paths).dicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
    }

    @Test func Rime目录里原有的配置先备份_永久保留() async throws {
        let b = try T.machine(withSettings: false); defer { b.dir.remove() }
        try FileManager.default.createDirectory(at: b.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("随手记\n".utf8).write(to: b.locations.rimeDirectory.appending(path: "notes.txt"))
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied(let applied) = report.outcome else { Issue.record("没有写入"); return }
        #expect(applied.backup.permanent)
        #expect(applied.backup.reason == "导入前")
        #expect(FileManager.default.fileExists(atPath: b.locations.rimeDirectory.appending(path: "notes.txt").path))
    }

    @Test func 输入习惯合并不上时配置照样导入() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let locked = T.Machine(dir: b.dir, paths: b.paths, locations: b.locations, squirrel: b.squirrel,
                               tool: FakeUserDBTool(lockedFailures: 99), catalog: b.catalog, packages: b.packages)
        let report = try await importer(locked).run(try await archive(for: locked), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied = report.outcome else { Issue.record("没有写入"); return }
        #expect(report.mergedUserDB == [])
        #expect(report.userDBError?.contains("别打字") == true)
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
    }

    @Test func 编译失败时什么都不保存() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        let report = try await importer(b, failing).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .compileFailed = report.outcome else { Issue.record("应该编译失败"); return }
        #expect(!FileManager.default.fileExists(atPath: b.paths.settingsFile.path))
        #expect(!FileManager.default.fileExists(atPath: b.paths.personal.path))
        #expect(b.tool.calls == [])
    }

    @Test func 打开了文本替换同步时带上新电脑的文本替换() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        var a = try await archive(for: b)
        var manifest = a.manifest
        manifest.settings.textReplacement.sync = true
        a = ImportArchive(manifest: manifest, personalDicts: a.personalDicts, phrases: a.phrases, userDB: a.userDB, warnings: a.warnings)
        let tr = Phrase(text: "新电脑的替换", code: "xdnd", weight: 1)
        _ = try await importer(b).run(a, catalog: b.catalog, packages: b.packages, textReplacement: [tr])
        let phrases = try String(contentsOf: b.locations.rimeDirectory.appending(path: "custom_phrase.txt"), encoding: .utf8)
        #expect(phrases.contains(tr.line))
    }
}
