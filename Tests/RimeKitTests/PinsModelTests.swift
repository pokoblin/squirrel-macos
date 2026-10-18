import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

/// 置顶列表和「有没应用的改动」（候选置顶设计 5.1、5.2）
@MainActor @Suite struct PinsModelTests {
    typealias T = TransferFixtures
    let kou = Phrase(text: "口", code: "kkkk", weight: nil)

    @Test func 置顶后有待应用的改动还原回去就没有() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(!model.hasPendingChanges)
        #expect(model.pins.pin(text: "口", code: "kkkk"))
        #expect(model.pins.phrases == [T.phrase, kou])
        #expect(model.pins.message == "已把「口」调到 kkkk 的第一位，点「应用改动」后生效")
        #expect(model.hasPendingChanges)
        model.unpin(kou)
        #expect(model.pins.phrases == [T.phrase])
        #expect(model.pins.message == "已还原 kkkk 的「口」，点「应用改动」后生效")
        #expect(!model.hasPendingChanges)
    }

    @Test func 同编码再置顶替换旧的() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.pins.pin(text: "口", code: "kkkk")
        model.pins.pin(text: "串口", code: "kkkk")
        #expect(model.pins.phrases == [T.phrase, Phrase(text: "串口", code: "kkkk", weight: nil)])
        #expect(model.pins.message == "已把「串口」调到 kkkk 的第一位，点「应用改动」后生效（替换了原来的「口」）")
    }

    @Test func 应用以后没有待应用的改动() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.pins.pin(text: "口", code: "kkkk")
        await model.apply()
        #expect(!model.pins.needsApply, "\(String(describing: model.notice))")
        #expect(!model.hasPendingChanges)
    }

    @Test func 正在应用时置顶不写文件() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        let lock = try ApplyLock.acquire(m.paths)
        defer { withExtendedLifetime(lock) {} }
        #expect(!model.pins.pin(text: "口", code: "kkkk"))
        #expect(model.pins.phrases == [T.phrase])
        #expect(model.pins.message == "正在应用改动，等一下再试")
        #expect(PhraseFile.parse(try String(contentsOf: m.paths.personalPhrases, encoding: .utf8)) == [T.phrase])
    }

    @Test func 不进试打页也能还原() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try FileManager.default.createDirectory(at: m.paths.personal, withIntermediateDirectories: true)
        try Data((PhraseFile.header + "口\tkkkk\n").utf8).write(to: m.paths.personalPhrases)
        let model = try MainModel(env: m.environment())
        #expect(model.pins.phrases == [kou])
        model.unpin(kou)
        #expect(!FileManager.default.fileExists(atPath: m.paths.personalPhrases.path))
    }

    @Test func 外面改过文件后置顶不覆盖外面的改动() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        let outside = Phrase(text: "外面加的", code: "wmjd", weight: nil)
        try Data((PhraseFile.header + PhraseFile.render([T.phrase, outside])).utf8).write(to: m.paths.personalPhrases)
        #expect(model.pins.pin(text: "口", code: "kkkk"))
        #expect(model.pins.phrases == [T.phrase, outside, kou])
        #expect(try PersonalPhraseStore(paths: m.paths).load() == [T.phrase, outside, kou])
    }

    @Test func 读不了的文件不当成空的() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let bad = Data([0xff, 0xfe, 0x00, 0x41])
        try bad.write(to: m.paths.personalPhrases)
        let model = try MainModel(env: m.environment())
        #expect(model.pins.problem?.contains("personal/phrases.txt") == true, "\(String(describing: model.pins.problem))")
        #expect(!model.pins.pin(text: "口", code: "kkkk"))
        #expect(model.pins.message?.contains("读不了") == true, "\(String(describing: model.pins.message))")
        #expect(try Data(contentsOf: m.paths.personalPhrases) == bad)
    }

    @Test func 点候选置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        let model = try MainModel(env: s.env)
        await model.preview.enter(draft: model.draft, hasPending: false)
        await s.engine.setInput(PreviewState(preedit: "kkkk",
                                             candidates: ["串口", "口"].map { PreviewCandidate(text: $0, comment: "") },
                                             input: "kkkk", wholeInput: true))
        await model.preview.press(.text("kkkk"))
        await model.pinCandidate(at: 0)   // 已经是第一个：不写
        #expect(model.pins.phrases == [T.phrase])
        await model.pinCandidate(at: 1)
        #expect(model.pins.phrases == [T.phrase, kou])
        await model.preview.leave()
    }

    @Test func 只对应前一段编码的候选点了也不置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        let model = try MainModel(env: s.env)
        await model.preview.enter(draft: model.draft, hasPending: false)
        await s.engine.setInput(PreviewState(preedit: "ni hao",
                                             candidates: ["你好", "你"].map { PreviewCandidate(text: $0, comment: "") },
                                             input: "nihao", wholeInput: true))
        await s.engine.setPartial([1])
        await model.preview.press(.text("nihao"))
        await model.pinCandidate(at: 1)
        #expect(model.pins.phrases == [T.phrase])
        #expect(model.pins.message == "「你」只对应前面一段编码，不能置顶")
        await model.preview.leave()
    }
}

/// 底栏「有改动还没应用」要把置顶说出来（审阅问题 3）
@MainActor @Suite struct PendingSummaryTests {
    typealias T = TransferFixtures

    @Test func 只改了置顶() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.pins.pin(text: "口", code: "kkkk")
        #expect(model.pendingSummary == "置顶有改动，还没应用")
    }

    @Test func 设置和置顶都改了时说清楚撤销不管置顶() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)
        #expect(model.pendingSummary == "有改动还没应用")
        model.pins.pin(text: "口", code: "kkkk")
        #expect(model.pendingSummary == "有改动还没应用（「撤销」只撤销设置，不撤销置顶的改动）")
    }
}

/// 应用以后不再挂着「点应用改动后生效」；导入前提醒会丢掉没应用的置顶（审阅后补）
@MainActor @Suite struct PinsAfterApplyTests {
    typealias T = TransferFixtures

    @Test func 应用以后清掉置顶的提示() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.pins.pin(text: "口", code: "kkkk")
        #expect(model.pins.message != nil)
        await model.apply()
        #expect(model.pins.message == nil)
    }

    @Test func 有没应用的置顶时导入前要提醒() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(!model.importDropsUnappliedEdits)
        model.pins.pin(text: "口", code: "kkkk")
        #expect(model.importDropsUnappliedEdits)
    }
}
