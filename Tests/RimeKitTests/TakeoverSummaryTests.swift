import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@Suite struct TakeoverSummaryTests {
    typealias F = TakeoverFixtures

    @Test func 摘要里只有名字和条数() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e)
        let preview = try TakeoverPreview.make(p, rime: e.rime, catalog: e.catalog, packages: e.packages,
                                               textReplacement: [F.fromTR], staging: e.dir.url.appending(path: "staging"))
        let s = TakeoverSummary.make(p, preview: preview, catalog: e.catalog, blockedReason: nil)
        #expect(s.schemas == ["五笔拼音（wb_py）", "五笔（wb）"])
        #expect(s.options == ["测试五笔 · 拼音词库：大词库"])
        #expect(s.appearance == ["候选字字号 24", "序号字号 20"])
        #expect(s.preservedPatches == ["default.custom.yaml：key_binder/bindings"])
        #expect(s.personalDicts == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(s.manualPhrases == 1)
        #expect(s.textReplacementMatches == 1)
        #expect(s.kept == ["notes.txt", "weasel.custom.yaml"])
        #expect(s.canConfirm)
        let text = "\(s)"
        for secret in ["私人短语", "替换短语", "私人词条", "私人五笔词"] {
            #expect(!text.contains(secret))
        }
    }

    @Test func 有阻止的原因时不能接管() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e)
        let preview = try TakeoverPreview.make(p, rime: e.rime, catalog: e.catalog, packages: e.packages,
                                               textReplacement: [], staging: e.dir.url.appending(path: "staging"))
        let s = TakeoverSummary.make(p, preview: preview, catalog: e.catalog, blockedReason: "读不了文本替换")
        #expect(!s.canConfirm)
        #expect(s.blockedReason == "读不了文本替换")
    }
}
