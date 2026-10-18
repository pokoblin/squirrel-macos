import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployerRestoreTests {
    func setup() async throws -> (DeployerTests.Env, Deployer) {
        let e = try DeployerTests().env(running: true)
        let deployer = e.deployer()
        guard case .applied = try await deployer.apply(try e.input(Settings(schemas: ["wb", "py"]))) else {
            throw CancellationError()
        }
        var settings = Settings(schemas: ["wb"])
        settings.appearance.fontPoint = 24
        guard case .applied = try await deployer.apply(try e.input(settings)) else { throw CancellationError() }
        return (e, deployer)
    }

    @Test func 还原到上一次应用前() async throws {
        let (e, deployer) = try await setup(); defer { e.dir.remove() }
        let backups = BackupStore(paths: e.paths).list()
        let beforeSecond = try #require(backups.first { $0.reason == "应用改动前" })
        let report = try await deployer.restore(beforeSecond.id)
        #expect(report.restored == beforeSecond)
        #expect(report.safetyBackup.reason == "还原前")
        #expect(FileManager.default.fileExists(atPath: e.rime.appending(path: "py.schema.yaml").path))
        #expect(!(try e.read("squirrel.custom.yaml")).contains("24"))
        #expect(try Ledger.load(e.paths) == beforeSecond.ledger)
        #expect(try Ledger.load(e.paths).externalChanges(in: e.rime).isEmpty)
        #expect(report.deploy.finished)
        #expect(e.squirrel.calls.last == "reload")
    }

    @Test func 账本记下短语指纹还原时跟着退回() async throws {
        let e = try DeployerTests().env(running: true); defer { e.dir.remove() }
        let deployer = e.deployer()
        let settings = Settings(schemas: ["wb"])
        guard case .applied = try await deployer.apply(try e.input(settings)) else { throw CancellationError() }
        #expect(try Ledger.load(e.paths).phrasesSHA256 == PhraseFile.fingerprint([]))

        let kou = Phrase(text: "口", code: "kkkk", weight: nil)
        try PersonalPhraseStore(paths: e.paths).save([kou])
        guard case .applied = try await deployer.apply(try e.input(settings)) else { throw CancellationError() }
        #expect(try Ledger.load(e.paths).phrasesSHA256 == PhraseFile.fingerprint([kou]))
        #expect(!PersonalPhraseStore(paths: e.paths).needsApply())

        let beforeSecond = try #require(BackupStore(paths: e.paths).list().first { $0.reason == "应用改动前" })
        _ = try await deployer.restore(beforeSecond.id)
        #expect(try Ledger.load(e.paths).phrasesSHA256 == PhraseFile.fingerprint([]))
        #expect(PersonalPhraseStore(paths: e.paths).needsApply())   // 手动短语还在，Rime 目录里已经没有了
    }

    @Test func 还原不存在的备份() async throws {
        let (e, deployer) = try await setup(); defer { e.dir.remove() }
        await #expect(throws: BackupError.notFound("nope")) { try await deployer.restore("nope") }
    }

    @Test func 状态() async throws {
        let (e, deployer) = try await setup(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "hand edited")
        let s = try deployer.status()
        #expect(s.squirrelInstalled)
        #expect(s.squirrelRunning)
        #expect(s.rimeDirectory == e.rime)
        #expect(s.managedFiles == (try Ledger.load(e.paths)).entries.count)
        #expect(s.externalChanges == [.modified("default.custom.yaml")])
        #expect(s.backups.count == 2)
    }
}

@Suite struct DeployerRestoreKeepsUnknownTests {
    @Test func 还原不删用户后来加的文件() async throws {
        let (e, deployer) = try await DeployerRestoreTests().setup(); defer { e.dir.remove() }
        try e.write("my_new_schema.schema.yaml", "mine")
        let target = try #require(BackupStore(paths: e.paths).list().first { $0.reason == "应用改动前" })
        _ = try await deployer.restore(target.id)
        #expect(try e.read("my_new_schema.schema.yaml") == "mine")
    }
}

@Suite struct DeployErrorMessageTests {
    @Test func 写入失败的提示里带备份id() {
        #expect(ApplyError.writeFailed("x", restored: false, backupID: "20261015-1").description.contains("rimectl restore 20261015-1"))
        #expect(ApplyError.writeFailed("x", restored: true, backupID: "20261015-1").description.contains("已经自动还原"))
    }

    @Test func 还原失败时自动回到还原前() async throws {
        let (e, deployer) = try await DeployerRestoreTests().setup(); defer { e.dir.remove() }
        let before = try e.read("squirrel.custom.yaml")
        let target = try #require(BackupStore(paths: e.paths).list().first { $0.reason == "应用改动前" })
        // 让备份里的 cn/a.dict.yaml 放不回去：把 cn 目录换成一个同名文件
        try FileManager.default.removeItem(at: e.rime.appending(path: "cn"))
        try Data("blocker".utf8).write(to: e.rime.appending(path: "cn"))
        let error = await #expect(throws: RestoreError.self) { try await deployer.restore(target.id) }
        guard case .failed(_, let safetyID, let rolledBack) = error else {
            Issue.record("应该是 RestoreError.failed，实际是 \(String(describing: error))")
            return
        }
        #expect(rolledBack)
        #expect(BackupStore(paths: e.paths).info(safetyID)?.reason == "还原前")
        #expect(try e.read("squirrel.custom.yaml") == before)
        #expect(error?.description.contains(safetyID) == true)
    }

    @Test func 还原最旧的那份后它不会被清理掉() async throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "patch: {}\n")
        // 先放 10 份旧的普通备份（时间从旧到新）
        var ids: [String] = []
        for day in 0..<10 {
            let store = BackupStore(paths: e.paths, now: { Date(timeIntervalSince1970: Double(day * 60)) })   // 比测试环境里 Deployer 的固定时间（1000 秒）早
            ids.append(try store.create(from: e.rime, reason: "应用改动前", permanent: false, ledger: Ledger()).id)
        }
        let oldest = ids[0]
        _ = try await e.deployer().restore(oldest)   // 还原前会再备份一份，一共 11 份普通备份
        #expect(BackupStore(paths: e.paths).info(oldest) != nil)
    }
}
