import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct AppStateTests {
    typealias T = TransferFixtures

    @Test func 已经设置好的直接进主窗口() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(m.paths)
        let state = AppState(env: m.environment())
        await state.start()
        #expect(state.main != nil)
        #expect(state.main?.notice == nil)
    }

    @Test func 没设置好的先走引导_走完点开始使用进主窗口() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let state = AppState(env: m.environment())
        await state.start()
        #expect(state.main == nil)
        #expect(state.setup.step == .chooseStart(.empty))
        await state.setup.useSettings(Settings(schemas: ["py"]))
        guard case .done(let lines) = state.setup.step else { Issue.record("\(state.setup.step)"); return }
        state.openMain(welcome: lines)
        #expect(state.main?.saved.schemas == ["py"])
        #expect(state.main?.notice?.lines == lines)
    }

    @Test func 打不开主窗口时说原因() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let state = AppState(env: m.environment())
        state.openMain(welcome: [])
        #expect(state.main == nil)
        #expect(state.openError?.contains("还没有设置") == true)
    }
}
