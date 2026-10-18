import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

/// 「方案」页的「检查更新」：方案清单和在用的方案包。只在点按钮时联网；有更新时「应用改动」可以点，退出再打开还提醒
@MainActor @Suite struct MainModelUpdateTests {
    typealias T = TransferFixtures
    typealias C = TestCatalogs

    /// 清单已经是最新的；wubi 包在上游有新版本（其余包和本地一样）
    func env(_ m: T.Machine, newer: Set<String> = ["wubi"], failing: Set<String> = []) -> AppEnvironment {
        let http = FakeHTTPClient()
        C.serve(http, try! C.online(m.catalog, serial: 0))
        var env = m.environment(catalogHTTP: http, catalogKeys: [C.publicKey])
        let packages = m.packages
        env.latestPackageVersion = { spec in
            if failing.contains(spec.id) { throw HTTPError.status(403, URL(string: "https://api.github.com/x")!) }
            let info = packages[spec.id]!.info
            return newer.contains(spec.id)
                ? ResolvedSource(version: "new-\(spec.id)", downloadURL: info.sourceURL, date: Self.day)
                : ResolvedSource(version: info.version, downloadURL: info.sourceURL)
        }
        return env
    }

    nonisolated static let day = ISO8601DateFormatter().date(from: "2026-10-17T03:00:00Z")!

    @Test func 都是最新的() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: env(m, newer: []))
        await model.checkUpdates()
        #expect(model.notice?.kind == .info)
        #expect(model.notice?.title == "都是最新的")
        #expect(model.notice?.lines.first == "方案清单：已经是最新的")
        #expect(model.notice?.lines.contains("测试五笔：已经是最新的") == true)
        #expect(!model.hasPendingChanges)
        #expect(model.working == nil)
    }

    @Test func 方案包有新版本_应用后清掉() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: env(m))
        await model.checkUpdates()
        #expect(model.notice?.title == "有更新")
        #expect(model.notice?.lines.contains("测试五笔：有新版本（上游 2026-10-17 更新）") == true)
        #expect(model.notice?.lines.last == "点「应用改动」就会用上新版本（会先备份）")
        #expect(model.packageUpdates == ["wubi"])
        #expect(model.hasPendingChanges)
        #expect(!model.isDirty)
        await model.apply()
        #expect(model.notice?.title == "改动已经生效")
        #expect(model.packageUpdates.isEmpty)
        #expect(!model.hasPendingChanges)
    }

    @Test func 退出再打开还提醒() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let first = try MainModel(env: env(m))
        await first.checkUpdates()
        first.catalogNeedsApply = true
        let again = try MainModel(env: env(m))
        #expect(again.packageUpdates == ["wubi"])
        #expect(again.catalogNeedsApply)
        #expect(again.hasPendingChanges)
        await again.apply()
        let third = try MainModel(env: env(m))
        #expect(!third.hasPendingChanges)
    }

    @Test func 用本地旧版本应用时包更新的提醒留着() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: env(m))
        await model.checkUpdates()
        await model.apply(usingCache: true)
        #expect(model.notice?.title == "改动已经生效")
        #expect(model.packageUpdates == ["wubi"])
    }

    @Test func 查不到的包单独说_不影响别的() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: env(m, newer: [], failing: ["wubi"]))
        await model.checkUpdates()
        #expect(model.notice?.kind == .warning)
        #expect(model.notice?.title == "有些没查到")
        #expect(model.notice?.lines.contains { $0.hasPrefix("测试五笔：没查到（") && $0.contains("403") } == true)
        #expect(model.notice?.lines.contains("测试拼音：已经是最新的") == true)
        #expect(model.packageUpdates.isEmpty)
    }

    @Test func 再查一次已经是最新的就不再提醒() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: env(m))
        await model.checkUpdates()
        #expect(model.packageUpdates == ["wubi"])
        var newer = model.env
        let packages = m.packages
        newer.latestPackageVersion = { spec in
            let info = packages[spec.id]!.info
            return ResolvedSource(version: info.version, downloadURL: info.sourceURL)
        }
        let again = try MainModel(env: newer)
        await again.checkUpdates()
        #expect(again.packageUpdates.isEmpty)
        #expect(!again.hasPendingChanges)
    }

    @Test func 和账本里记的版本比() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        var ledger = try Ledger.load(m.paths)
        ledger.packages = ["wubi": "older"]   // 应用时用的是旧版本，本地缓存后来下了新的
        try ledger.save(m.paths)
        let model = try MainModel(env: env(m, newer: []))
        await model.checkUpdates()
        #expect(model.packageUpdates == ["wubi"])
    }

    @Test func 导入时更新了清单但导入失败_记着要应用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let model = try MainModel(env: m.environment(catalogHTTP: http, catalogKeys: [C.publicKey]))
        await model.importFile(try C.exportFile(schemas: ["extra"], in: m.dir.url))   // 假电脑没有 extra 包，会失败
        #expect(model.notice?.kind == .error)
        #expect(model.catalogNeedsApply)
    }
}
