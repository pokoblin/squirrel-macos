import Foundation
import Testing
@testable import RimeKit

@Suite struct UserDBTransferTests {
    func squirrel(_ dir: TempDir, running: Bool) throws -> FakeSquirrel {
        FakeSquirrel(locations: try DeployFixtures.locations(dir), running: running)
    }

    func transfer(_ tool: FakeUserDBTool, _ squirrel: FakeSquirrel) -> UserDBTransfer {
        UserDBTransfer(tool: tool, squirrel: squirrel, sleep: { _ in })
    }

    @Test func 导出前退出鼠须管_导完重新启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tool = FakeUserDBTool(dbs: ["b": "快照b\n", "a": "快照a\n"])
        let s = try squirrel(dir, running: true)
        let out = dir.url.appending(path: "userdb", directoryHint: .isDirectory)
        #expect(try await transfer(tool, s).exportAll(into: out).names == ["a", "b"])
        #expect(try String(contentsOf: out.appending(path: "a.userdb.txt"), encoding: .utf8) == "快照a\n")
        #expect(try String(contentsOf: out.appending(path: "b.userdb.txt"), encoding: .utf8) == "快照b\n")
        #expect(s.calls == ["quit", "launch"])
    }

    @Test func 鼠须管原来没运行_导出后也不启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: false)
        _ = try await transfer(FakeUserDBTool(dbs: ["a": "x\n"]), s).exportAll(into: dir.url.appending(path: "u"))
        #expect(s.calls == [])
    }

    @Test func 没有输入习惯时什么都不做() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        #expect(try await transfer(FakeUserDBTool(), s).exportAll(into: dir.url.appending(path: "u")).names == [])
        #expect(s.calls == [])
    }

    @Test func 被占着时重试() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tool = FakeUserDBTool(dbs: ["a": "x\n"], lockedFailures: 2)
        let s = try squirrel(dir, running: true)
        #expect(try await transfer(tool, s).exportAll(into: dir.url.appending(path: "u")).names == ["a"])
        #expect(tool.calls == ["export a"])
        #expect(s.calls.last == "launch")
    }

    @Test func 一直被占着就报错_鼠须管还是会启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tool = FakeUserDBTool(dbs: ["a": "x\n"], lockedFailures: 99)
        let s = try squirrel(dir, running: true)
        await #expect(throws: UserDBError.stillLocked("a")) {
            try await transfer(tool, s).exportAll(into: dir.url.appending(path: "u"))
        }
        #expect(s.calls.last == "launch")
    }

    @Test func 合并后启动鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "a.userdb.txt")
        try Data("新的\n".utf8).write(to: file)
        let tool = FakeUserDBTool(dbs: ["a": "旧的\n"])
        let s = try squirrel(dir, running: false)
        #expect(try await transfer(tool, s).importAll(["a": file]).names == ["a"])
        #expect(tool.dbs["a"] == "旧的\n新的\n")
        #expect(s.calls == ["launch"])
    }

    @Test func 合并好了_最后启动鼠须管失败只是提醒() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "a.userdb.txt")
        try Data("新的\n".utf8).write(to: file)
        let tool = FakeUserDBTool(dbs: ["a": "旧的\n"])
        let s = try squirrel(dir, running: false)
        s.launchError = .commandFailed("open", "测试")
        let result = try await transfer(tool, s).importAll(["a": file])
        #expect(result.names == ["a"])
        #expect(result.warning?.contains("启动鼠须管") == true)
    }
}
