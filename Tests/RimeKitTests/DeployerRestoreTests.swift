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
