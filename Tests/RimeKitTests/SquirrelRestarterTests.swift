import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelRestarterTests {
    func squirrel(_ dir: TempDir, running: Bool) throws -> FakeSquirrel {
        FakeSquirrel(locations: try DeployFixtures.locations(dir), running: running)
    }

    func restarter(_ squirrel: FakeSquirrel) -> SquirrelRestarter {
        SquirrelRestarter(squirrel: squirrel, sleep: { _ in })
    }

    @Test func 在运行时先退出再启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        try await restarter(s).restart()
        #expect(s.calls == ["quit", "launch"])
        #expect(s.isRunning())
    }

    @Test func 没在运行时直接启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: false)
        try await restarter(s).restart()
        #expect(s.calls == ["launch"])
    }

    @Test func 普通退出没反应时强制退出() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        s.ignoresQuit = true
        try await restarter(s).restart()
        #expect(s.calls == ["quit", "forceQuit", "launch"])
        #expect(s.isRunning())
    }

    @Test func 强制退出也没用时不启动_报错() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        s.ignoresQuit = true
        s.forceKillWorks = false
        await #expect(throws: SquirrelError.stillRunning) { try await restarter(s).restart() }
        #expect(s.calls == ["quit", "forceQuit"])
    }

    @Test func 启动命令失败时报错() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        s.launchError = .commandFailed("open 鼠须管", "boom")
        await #expect(throws: SquirrelError.commandFailed("open 鼠须管", "boom")) { try await restarter(s).restart() }
    }

    @Test func 启动后进程没起来时报错() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        s.launchDoesNothing = true
        await #expect(throws: SquirrelError.notStarted) { try await restarter(s).restart() }
    }
}
