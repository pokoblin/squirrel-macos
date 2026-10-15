import Foundation
import Testing
@testable import RimeKit

@Suite struct BackupStoreTests {
    func write(_ dir: URL, _ path: String, _ text: String) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ dir: URL, _ path: String) throws -> String {
        try String(contentsOf: dir.appending(path: path), encoding: .utf8)
    }

    @Test func 只备份配置文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "default.custom.yaml", "d")
        try write(rime, "cn_dicts/a.dict.yaml", "a")
        try write(rime, "build/default.yaml", "b")
        try write(rime, "user.yaml", "u")
        let store = BackupStore(paths: Fixtures.paths(dir))
        let ledger = Ledger(entries: ["default.custom.yaml": LedgerEntry(sha256: "x", origin: "generated")])
        let info = try store.create(from: rime, reason: "测试", permanent: true, ledger: ledger)
        #expect(info.files == ["cn_dicts/a.dict.yaml", "default.custom.yaml"])
        #expect(info.permanent)
        #expect(info.ledger == ledger)
        #expect(store.list() == [info])
        #expect(store.info(info.id) == info)
    }

    @Test func 新的在前带partial的不算() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "a.yaml", "a")
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let store = BackupStore(paths: Fixtures.paths(dir), now: clock.next)
        let first = try store.create(from: rime, reason: "1", permanent: false, ledger: Ledger())
        let second = try store.create(from: rime, reason: "2", permanent: false, ledger: Ledger())
        try FileManager.default.createDirectory(at: Fixtures.paths(dir).backups.appending(path: "x.partial"), withIntermediateDirectories: true)
        #expect(store.list().map(\.id) == [second.id, first.id])
    }

    @Test func 清理时保留最近的和永久的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "a.yaml", "a")
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let store = BackupStore(paths: Fixtures.paths(dir), now: clock.next)
        let keeper = try store.create(from: rime, reason: "第一次应用前", permanent: true, ledger: Ledger())
        var normal: [BackupInfo] = []
        for i in 0..<5 { normal.append(try store.create(from: rime, reason: "\(i)", permanent: false, ledger: Ledger())) }
        let removed = try store.prune(keep: 3)
        #expect(removed == [normal[1].id, normal[0].id])
        #expect(store.list().map(\.id) == [normal[4].id, normal[3].id, normal[2].id, keeper.id])
    }

    @Test func 还原成备份时的样子而且不动Rime自己的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "a.yaml", "old")
        try write(rime, "keep/b.yaml", "b")
        let store = BackupStore(paths: Fixtures.paths(dir))
        let info = try store.create(from: rime, reason: "前", permanent: false, ledger: Ledger())
        try write(rime, "a.yaml", "new")
        try write(rime, "added.yaml", "x")
        try FileManager.default.removeItem(at: rime.appending(path: "keep/b.yaml"))
        try write(rime, "user.yaml", "runtime")
        _ = try store.restore(info.id, to: rime)
        #expect(try RimeFiles.configFiles(in: rime) == ["a.yaml", "keep/b.yaml"])
        #expect(try read(rime, "a.yaml") == "old")
        #expect(try read(rime, "user.yaml") == "runtime")
    }

    @Test func 还原不存在的备份() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(throws: BackupError.notFound("nope")) {
            try BackupStore(paths: Fixtures.paths(dir)).restore("nope", to: dir.url)
        }
    }
}
