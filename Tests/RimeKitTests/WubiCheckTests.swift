import Foundation
import Synchronization
import Testing
@testable import RimeKit

/// 假的引擎：按编码返回预先排好的候选页，记下 open 的参数
private final class FakeEngine: PreviewEngine {
    private struct Inner {
        var opened: [String] = []
        var code = ""
        var page = 0
    }
    private let inner = Mutex(Inner())
    private let pages: [String: [[String]]]

    init(pages: [String: [[String]]]) { self.pages = pages }

    var opened: [String] { inner.withLock { $0.opened } }

    private func state(_ i: Inner) -> PreviewState {
        let all = pages[i.code] ?? []
        guard i.page < all.count else { return PreviewState() }
        return PreviewState(
            preedit: i.code, candidates: all[i.page].map { PreviewCandidate(text: $0, comment: "") },
            pageNo: i.page, isLastPage: i.page == all.count - 1)
    }

    func open(userDir: URL, schema: String) async throws -> PreviewOpened {
        inner.withLock { $0.opened.append("\(userDir.lastPathComponent):\(schema)") }
        return PreviewOpened(librimeVersion: "fake", state: .empty)
    }
    func input(_ text: String) async throws -> PreviewState {
        inner.withLock { $0.code = text; $0.page = 0; return state($0) }
    }
    func key(_ key: PreviewKey) async throws -> PreviewState {
        inner.withLock { if key == .pageDown { $0.page += 1 }; return state($0) }
    }
    func select(_ index: Int) async throws -> PreviewState { inner.withLock { state($0) } }
    func clear() async throws -> PreviewState { inner.withLock { $0.code = ""; $0.page = 0; return .empty } }
    func close() async {}
}

struct WubiCheckTests {
    /// 索引：wqiy 下 你(20)、仰泳(10)；wq 下 仰(100)
    private static func index() throws -> WubiCodeIndex {
        try WubiCodeIndex(main: DictFile.parse(WubiFixtures.mainDict), imports: [])
    }

    @Test func 三种结果() async throws {
        let index = try Self.index()
        // wqiy 预期：你、仰泳。引擎里被一个别的词挤到前面，仰泳 实际排第 3
        let engine = FakeEngine(pages: [
            "wqiy": [["你", "别的"], ["仰泳"]],
            "wq": [["仰"]],
        ])
        let results = try await WubiCheck.run(
            [
                DictEntry(text: "你", code: "wqiy"),     // 预期 0，实际 0
                DictEntry(text: "仰泳", code: "wqiy"),   // 预期 1，实际 2（第 2 页第 1 个）
                DictEntry(text: "仰", code: "wq"),
                DictEntry(text: "没有", code: "wqiy"),   // 引擎里没有
                DictEntry(text: "新词", code: nil),       // 没编码
                DictEntry(text: "外面的", code: "wq"),    // 引擎里没有
            ],
            index: index, engine: engine, userDir: URL(fileURLWithPath: "/tmp/x"), schema: "wubi86_jidian")
        #expect(results == [
            .asExpected(page: 0, index: 0),
            .elsewhere(page: 1, index: 0),
            .asExpected(page: 0, index: 0),
            .missing,
            .missing,
            .missing,
        ])
        #expect(engine.opened == ["x:wubi86_jidian"])
    }

    @Test func 词不在索引里算别处() async throws {
        let engine = FakeEngine(pages: ["wq": [["仰", "新"]]])
        let results = try await WubiCheck.run(
            [DictEntry(text: "新", code: "wq")],
            index: Self.index(), engine: engine, userDir: URL(fileURLWithPath: "/tmp/x"), schema: "s")
        #expect(results == [.elsewhere(page: 0, index: 1)])
    }

    @Test func 选检查用的方案() {
        let t = WubiDictTarget.jidian
        #expect(WubiCheck.checkSchema(
            in: Settings(schemas: ["rime_ice", "wubi86_jidian_pinyin", "wubi86_jidian"]), target: t)
            == "wubi86_jidian_pinyin")
        // 简入繁出方案会把简体词转成繁体，只在没有别的极点方案时才用
        #expect(WubiCheck.checkSchema(
            in: Settings(schemas: ["wubi86_jidian_trad", "wubi86_jidian_pinyin"]), target: t)
            == "wubi86_jidian_pinyin")
        #expect(WubiCheck.checkSchema(
            in: Settings(schemas: ["wubi86_jidian_trad_pinyin", "rime_ice"]), target: t)
            == "wubi86_jidian_trad_pinyin")
        #expect(WubiCheck.checkSchema(in: Settings(schemas: ["rime_ice"]), target: t) == nil)
        #expect(WubiCheck.checkSchema(in: Settings(schemas: []), target: t) == nil)
    }
}

/// 真的 PreviewSession 加编译好的极点五笔夹具（需要装好鼠须管）
@Suite(.enabled(if: RimeTools.installed))
struct WubiCheckIntegrationTests {
    @Test(.timeLimit(.minutes(1))) func 加的词排在中间() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let userDict = WubiFixtures.userDict + "\n仰咏\twqiy\t15\n"
        let rime = try WubiFixtures.compiled(in: dir.url.appending(path: "rime"), userDict: userDict)
        let index = try WubiCodeIndex.load(
            from: WubiFixtures.makePackage(in: dir.url.appending(path: "cache")),
            personalUserDict: rime.appending(path: WubiFixtures.userName), target: .jidian)
        let session = PreviewSession(helper: PreviewFixtures.helper)
        let results = try await WubiCheck.run(
            [DictEntry(text: "仰咏", code: "wqiy", weight: 15)],
            index: index, engine: session, userDir: rime, schema: "wubi86_jidian")
        await session.close()
        // 你 20、仰咏 15、仰泳 10
        #expect(results == [.asExpected(page: 0, index: 1)])
    }
}
