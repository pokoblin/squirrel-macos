import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverApplierTests {
    typealias F = TakeoverFixtures

    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let catalog: Catalog
        let packages: [String: CachedPackage]
        let squirrel: FakeSquirrel

        func deployer(_ compiler: FakeCompiler = FakeCompiler()) -> Deployer {
            Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                     watcher: DeployFixtures.watcher(locations))
        }

        func proposal() throws -> TakeoverProposal {
            let survey = try TakeoverSurvey.scan(locations.rimeDirectory, catalog: catalog)
            return try TakeoverAnalyzer.analyze(locations.rimeDirectory, catalog: catalog, survey: survey,
                                                packages: packages, textReplacement: [F.fromTR])
        }

        func confirm(_ compiler: FakeCompiler = FakeCompiler(), force: Bool = false) async throws -> ApplyOutcome {
            try await TakeoverApplier(deployer: deployer(compiler))
                .confirm(try proposal(), catalog: catalog, packages: packages, textReplacement: [F.fromTR], force: force)
        }
    }

    func env() throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let packages = try GenFixtures.makePackages(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        try F.wubiSample(packages, into: locations.rimeDirectory)
        return Env(dir: dir, paths: paths, locations: locations, catalog: try GenFixtures.catalog(), packages: packages,
                   squirrel: FakeSquirrel(locations: locations, running: true))
    }

    @Test func 确认后写入并保存设置和个人内容() async throws {
        let e = try env(); defer { e.dir.remove() }
        let expected = try e.proposal()
        guard case .applied(let report) = try await e.confirm() else { Issue.record("没有写入"); return }
        #expect(report.backup.permanent)
        #expect(try SettingsStore(paths: e.paths).load() == expected.settings)
        let personal = try PersonalContent.load(from: e.paths)
        #expect(personal.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(personal.phrases == [F.manual])
        #expect(!(try Ledger.load(e.paths).entries.isEmpty))
        // 应用不认识的文件原样保留
        #expect(try String(contentsOf: e.locations.rimeDirectory.appending(path: "notes.txt"), encoding: .utf8) == "随手记的东西\n")
        #expect(try String(contentsOf: e.locations.rimeDirectory.appending(path: "weasel.custom.yaml"), encoding: .utf8) == "patch:\n  style/font_point: 20\n")
    }

    /// 通知鼠须管时看一眼设置和个人内容存好了没有
    final class WatchingSquirrel: SquirrelControlling, @unchecked Sendable {
        let paths: AppPaths
        var seen: [Bool] = []
        init(paths: AppPaths) { self.paths = paths }
        func isRunning() -> Bool { true }
        func reload() throws {
            seen.append(FileManager.default.fileExists(atPath: paths.settingsFile.path)
                        && FileManager.default.fileExists(atPath: paths.personalDicts.appending(path: "wb_user.dict.yaml").path))
        }
        func launch() throws { try reload() }
        func registerInputSource() throws {}
        func quit() throws {}
    }

    @Test func 等部署之前就保存好设置和个人内容() async throws {
        // 等部署最多两分钟：这时中断（Ctrl-C、应用退出）也不能留下「目录已接管、设置却没有」的状态
        let e = try env(); defer { e.dir.remove() }
        let squirrel = WatchingSquirrel(paths: e.paths)
        let deployer = Deployer(paths: e.paths, locations: e.locations, compiler: FakeCompiler(), squirrel: squirrel,
                                watcher: DeployFixtures.watcher(e.locations))
        _ = try await TakeoverApplier(deployer: deployer)
            .confirm(try e.proposal(), catalog: e.catalog, packages: e.packages, textReplacement: [F.fromTR], force: false)
        #expect(squirrel.seen == [true])
    }

    @Test func 接管后再应用一次什么都不写() async throws {
        let e = try env(); defer { e.dir.remove() }
        guard case .applied = try await e.confirm() else { Issue.record("没有写入"); return }
        let settings = try #require(try SettingsStore(paths: e.paths).load())
        let input = GenerationInput(settings: settings, catalog: e.catalog, packages: e.packages,
                                    personal: try PersonalContent.load(from: e.paths), textReplacementPhrases: [F.fromTR])
        guard case .applied(let again) = try await e.deployer().apply(input) else { Issue.record("第二次没有写入"); return }
        #expect(again.written == [])
        #expect(again.removed == [])
    }

    @Test func 已经有设置时不加force就不接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        try SettingsStore(paths: e.paths).save(Settings(schemas: ["wb"]))
        await #expect(throws: TakeoverError.settingsExist(e.paths.settingsFile.path)) { try await e.confirm() }
        #expect(try Ledger.load(e.paths).entries.isEmpty)
        guard case .applied = try await e.confirm(force: true) else { Issue.record("加了 force 也没有写入"); return }
    }

    @Test func 已经由应用管理时不接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(e.paths)
        await #expect(throws: TakeoverError.alreadyManaged) { try await e.confirm() }
    }

    @Test func 编译失败时什么都不保存() async throws {
        let e = try env(); defer { e.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        guard case .compileFailed = try await e.confirm(failing) else { Issue.record("应该编译失败"); return }
        #expect(!FileManager.default.fileExists(atPath: e.paths.settingsFile.path))
        #expect(!FileManager.default.fileExists(atPath: e.paths.personal.path))
        #expect(try Ledger.load(e.paths).entries.isEmpty)
    }
}
