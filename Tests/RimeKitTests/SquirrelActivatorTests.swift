import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelActivatorTests {
    func make(_ dir: TempDir, _ input: FakeInputSource, running: Bool, timeout: Double = 5) throws -> (SquirrelActivator, FakeSquirrel) {
        let l = try DeployFixtures.locations(dir)
        let squirrel = FakeSquirrel(locations: l, running: running)
        let activator = SquirrelActivator(locations: l, inputSource: input, squirrel: squirrel,
                                          watcher: DeployFixtures.watcher(l), timeout: timeout, pollInterval: 1)
        return (activator, squirrel)
    }

    @Test func 用户添加后切换过去并启动鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        input.enableAfterPumps = 3
        let (activator, squirrel) = try make(dir, input, running: false)
        let waited = Flag()
        let outcome = try await activator.activate(onWaiting: { waited.set() })
        #expect(outcome == .ready(openedSettings: true, launched: true))
        #expect(input.calls == ["open", "select"])
        #expect(input.pumpCount == 3)
        #expect(waited.isSet)
        #expect(squirrel.calls == ["launch"])
    }

    @Test func 已经添加好也选中了就什么都不用做() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true))
        let (activator, squirrel) = try make(dir, input, running: true)
        #expect(try await activator.activate() == .ready(openedSettings: false, launched: false))
        #expect(input.calls.isEmpty)
        #expect(squirrel.calls.isEmpty)
    }

    @Test func 用户一直不添加就超时() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        let (activator, _) = try make(dir, input, running: false, timeout: 3)
        #expect(try await activator.activate() == .timedOut)
        #expect(input.pumpCount == 3)
        #expect(!input.calls.contains("select"))
    }

    @Test func 没注册时先重新注册然后让用户再运行一次() async throws {
        // 测试机实测：输入源消失又回来后，同一个进程里看到的「已启用」一直是旧的（false），
        // pump、本进程注册、发通知都刷新不了，新进程才看得到。所以回来后就停下，不去打开系统设置白等
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: false, enabled: false, selected: false))
        let (activator, squirrel) = try make(dir, input, running: true)
        squirrel.onRegister = { input.changeOnNextPump(to: InputSourceState(registered: true, enabled: false, selected: false)) }
        let registering = Flag()
        let outcome = try await activator.activate(onRegistering: { registering.set() })
        #expect(outcome == .reregistered)
        #expect(squirrel.calls == ["register"])
        #expect(registering.isSet)
        #expect(input.pumpCount == 1)   // 注册后要让 run loop 转一下，TIS 的缓存才会更新
        #expect(input.calls.isEmpty)
    }

    @Test func 重新注册后还是没有() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: false, enabled: false, selected: false))
        let (activator, squirrel) = try make(dir, input, running: false)
        #expect(try await activator.activate() == .notRegistered)
        #expect(squirrel.calls == ["register"])
        #expect(input.pumpCount == 5)   // 最多等 5 秒
        #expect(input.calls.isEmpty)
    }

    @Test func 注册命令失败要报出来() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: false, enabled: false, selected: false))
        let (activator, squirrel) = try make(dir, input, running: false)
        squirrel.registerError = .commandFailed("Squirrel --register-input-source", "boom")
        await #expect(throws: SquirrelError.commandFailed("Squirrel --register-input-source", "boom")) {
            try await activator.activate()
        }
    }

    @Test func 没装鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        var l = try DeployFixtures.locations(dir)
        l.squirrelApp = dir.url.appending(path: "None.app")
        let input = FakeInputSource(InputSourceState(registered: false, enabled: false, selected: false))
        let activator = SquirrelActivator(locations: l, inputSource: input, squirrel: FakeSquirrel(locations: l, running: false),
                                          watcher: DeployFixtures.watcher(l), timeout: 1, pollInterval: 1)
        await #expect(throws: ApplyError.squirrelNotInstalled) { try await activator.activate() }
    }

    @Test func 切换失败要报出来() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: false))
        input.selectError = .selectFailed(-50)
        let (activator, _) = try make(dir, input, running: true)
        await #expect(throws: InputSourceError.selectFailed(-50)) { try await activator.activate() }
    }

    @Test func 启动鼠须管前告诉界面() async throws {
        // 加好输入法后还要启动鼠须管、等第一次部署（最长两分钟），界面要换成「正在启动」
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true))
        let (activator, _) = try make(dir, input, running: false)
        let launching = Flag()
        _ = try await activator.activate(onLaunching: { launching.set() })
        #expect(launching.isSet)
    }
}

/// 线程安全的「发生过没有」
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
