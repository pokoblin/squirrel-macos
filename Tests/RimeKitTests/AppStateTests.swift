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

    @Test func 打开时文本替换有变化就提示同步() async throws {
        // 设计 6.5：应用启动时检查，有变化就问要不要同步
        let m = try T.machine(); defer { m.dir.remove() }
        let a = Phrase(text: "替换甲", code: "tha", weight: 1)
        let b = Phrase(text: "替换乙", code: "thb", weight: 1)
        let first = try MainModel(env: m.environment(textReplacements: {
            TextReplacementSnapshot(usable: [a], badShortcut: 0, badPhrase: 0)
        }))
        first.draft.textReplacement.sync = true
        await first.apply()   // 上次同步时只有 a
        let state = AppState(env: m.environment(textReplacements: {
            TextReplacementSnapshot(usable: [a, b], badShortcut: 0, badPhrase: 0)
        }))
        await state.start()
        let notice = try #require(state.main?.notice)
        #expect(notice.action == .syncTextReplacement)
        #expect(notice.lines.contains { $0.contains("新增 1 条") })
        await state.main?.perform(.syncTextReplacement)
        await state.main?.checkTextReplacement()
        #expect(state.main?.textReplacementStatus?.changes == TextReplacementSync.Changes(added: 0, removed: 0))
    }

    @Test func 打开时文本替换没变化不提示() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(m.paths)
        let a = Phrase(text: "替换甲", code: "tha", weight: 1)
        var settings = T.settings
        settings.textReplacement.sync = true
        try SettingsStore(paths: m.paths).save(settings.recordingTextReplacement([a]))
        let state = AppState(env: m.environment(textReplacements: {
            TextReplacementSnapshot(usable: [a], badShortcut: 0, badPhrase: 0)
        }))
        await state.start()
        #expect(state.main != nil)
        #expect(state.main?.notice == nil)
    }
}
