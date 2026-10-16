import Foundation
import Synchronization
import Testing
@testable import RimeKit

/// 假的引擎：按编码返回预先排好的几页候选，记下每次调用
private final class FakeEngine: PreviewEngine {
    private struct Inner {
        var calls: [String] = []
        var code = ""
        var page = 0
    }
    private let inner = Mutex(Inner())
    private let pages: [String: [[String]]]
    private let commitOnInput: [String: String]

    init(pages: [String: [[String]]], commitOnInput: [String: String] = [:]) {
        self.pages = pages
        self.commitOnInput = commitOnInput
    }

    var calls: [String] { inner.withLock { $0.calls } }

    private func state(_ i: Inner, committed: String? = nil) -> PreviewState {
        let all = pages[i.code] ?? []
        guard i.page < all.count else { return PreviewState(committed: committed) }
        return PreviewState(
            committed: committed, preedit: i.code,
            candidates: all[i.page].map { PreviewCandidate(text: $0, comment: "") },
            pageNo: i.page, isLastPage: i.page == all.count - 1)
    }

    func open(userDir: URL, schema: String) async throws -> PreviewOpened {
        PreviewOpened(librimeVersion: "fake", state: .empty)
    }

    func input(_ text: String) async throws -> PreviewState {
        inner.withLock {
            $0.calls.append("input:\(text)")
            $0.code = text
            $0.page = 0
            return state($0, committed: commitOnInput[text])
        }
    }

    func key(_ key: PreviewKey) async throws -> PreviewState {
        inner.withLock {
            $0.calls.append("key:\(key)")
            if key == .pageDown { $0.page += 1 }
            return state($0)
        }
    }

    func select(_ index: Int) async throws -> PreviewState {
        inner.withLock { $0.calls.append("select:\(index)"); return state($0) }
    }

    func clear() async throws -> PreviewState {
        inner.withLock { $0.calls.append("clear"); $0.code = ""; $0.page = 0; return .empty }
    }

    func close() async {}
}

struct PreviewProbeTests {
    private static let threePages: [String: [[String]]] = [
        "nihao": [["你好", "你"], ["尼", "泥"], ["妮", "霓", "逆"]],
    ]

    @Test func 第一页就有() async throws {
        let fake = FakeEngine(pages: Self.threePages)
        let m = try await PreviewProbe.find("你好", code: "nihao", in: fake)
        #expect(m == PreviewMatch(page: 0, index: 0, overall: 0, autoCommitted: false))
        #expect(!fake.calls.contains("key:pageDown"))
    }

    @Test func 翻页才找到() async throws {
        let fake = FakeEngine(pages: Self.threePages)
        let m = try await PreviewProbe.find("霓", code: "nihao", in: fake)
        #expect(m == PreviewMatch(page: 2, index: 1, overall: 5, autoCommitted: false))
        #expect(fake.calls.filter { $0 == "key:pageDown" }.count == 2)
    }

    @Test func 每页五个时总位置() async throws {
        let pages = ["abcd": [["a1", "a2", "a3", "a4", "a5"], ["b1", "b2", "b3", "b4", "b5"], ["c1", "c2", "c3"]]]
        let fake = FakeEngine(pages: pages)
        let m = try await PreviewProbe.find("c2", code: "abcd", in: fake)
        #expect(m == PreviewMatch(page: 2, index: 1, overall: 11, autoCommitted: false))
    }

    @Test func 自动上屏() async throws {
        let fake = FakeEngine(pages: ["yi": [["一"]]], commitOnInput: ["yi": "一"])
        let m = try await PreviewProbe.find("一", code: "yi", in: fake)
        #expect(m == PreviewMatch(page: 0, index: 0, overall: 0, autoCommitted: true))
    }

    @Test func 找不到() async throws {
        // 翻到最后一页也没有
        let a = FakeEngine(pages: Self.threePages)
        #expect(try await PreviewProbe.find("没有", code: "nihao", in: a) == nil)
        #expect(a.calls.filter { $0 == "key:pageDown" }.count == 2)
        // 没到最后一页，但超过 maxPages：只看 2 页，pageDown 最多 1 次
        let b = FakeEngine(pages: Self.threePages)
        #expect(try await PreviewProbe.find("霓", code: "nihao", maxPages: 2, in: b) == nil)
        #expect(b.calls.filter { $0 == "key:pageDown" }.count == 1)
        // 编码根本没有候选
        let c = FakeEngine(pages: [:])
        #expect(try await PreviewProbe.find("你好", code: "zzz", in: c) == nil)
    }

    @Test func 先清空() async throws {
        let fake = FakeEngine(pages: Self.threePages)
        _ = try await PreviewProbe.find("你好", code: "nihao", in: fake)
        #expect(fake.calls.first == "clear")
        #expect(fake.calls.dropFirst().first == "input:nihao")
    }
}

/// 真的 PreviewSession 加编译好的配置（需要装好鼠须管）
@Suite(.enabled(if: RimeTools.installed))
struct PreviewProbeIntegrationTests {
    @Test(.timeLimit(.minutes(1))) func 找到第二页的揖() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url, pageSize: 5)
        let session = PreviewSession(helper: PreviewFixtures.helper)
        _ = try await session.open(userDir: rime, schema: "py")
        let m = try await PreviewProbe.find("揖", code: "yi", in: session)
        await session.close()
        #expect(m == PreviewMatch(page: 1, index: 1, overall: 6, autoCommitted: false))
    }
}
