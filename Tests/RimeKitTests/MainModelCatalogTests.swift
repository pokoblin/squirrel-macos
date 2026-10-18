import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

/// 假电脑的设置启用了 wb_py（包 wubi）、py（包 pinyin），「大词库」选项用到 words
@MainActor @Suite struct MainModelCatalogTests {
    typealias T = TransferFixtures
    typealias C = TestCatalogs

    func model(_ m: T.Machine, _ http: FakeHTTPClient) throws -> MainModel {
        try MainModel(env: m.environment(catalogHTTP: http, catalogKeys: [C.publicKey]))
    }

    @Test func 已经是最新的() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 0))
        let model = try model(m, http)
        await model.checkUpdates()
        #expect(model.notice?.title == "都是最新的")
        #expect(model.notice?.lines.first == "方案清单：已经是最新的")
        #expect(!model.hasPendingChanges)
        #expect(model.working == nil)
    }

    @Test func 在用的包规则变了要重新应用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.set("wubi", "include", ["*", "lua/**"])))
        let model = try model(m, http)
        await model.checkUpdates()
        #expect(model.notice?.title == "有更新")
        #expect(model.notice?.lines.prefix(2) == ["方案清单更新了", "你在用的这些方案包的安装规则变了：测试五笔。应用改动后生效"])
        #expect(model.catalogNeedsApply)
        #expect(model.hasPendingChanges)
        #expect(!model.isDirty)
        #expect(model.catalogStatus.catalog.serial == 5)
        await model.apply()
        #expect(model.notice?.title == "改动已经生效")
        #expect(!model.catalogNeedsApply)
        #expect(!model.hasPendingChanges)
    }

    @Test func 新增方案出现在可以启用的列表里() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let model = try model(m, http)
        await model.checkUpdates()
        #expect(model.catalogPackages.map(\.id).contains("extra"))
        #expect(!model.catalogNeedsApply)
    }

    @Test func 签名不对时不采用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5), signature: C.sign(Data("别的".utf8)))
        let model = try model(m, http)
        await model.checkUpdates()
        #expect(model.notice?.kind == .warning)
        #expect(model.notice?.title == "有些没查到")
        #expect(model.notice?.lines.first == "方案清单没有用上新的：方案清单的签名不对，没有采用。如果方案清单刚发布不久，GitHub 可能还在给旧文件，过几分钟再试。继续用现在的方案清单")
        #expect(model.catalogStatus.catalog.serial == 0)
    }

    @Test func 下架的包不再列出_在用的除外() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5) { packages in
            C.addPackage(copying: "pinyin", as: "old", schema: "old1", deprecated: true)(&packages)
            C.set("wubi", "deprecated", true)(&packages)
        })
        let model = try model(m, http)
        await model.checkUpdates()
        let ids = model.catalogPackages.map(\.id)
        #expect(!ids.contains("old"))
        #expect(ids.contains("wubi"))
    }

    @Test func 导入时不认识的方案先更新清单() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let env = m.environment(catalogHTTP: http, catalogKeys: [C.publicKey])
        let model = try MainModel(env: env)
        let file = try C.exportFile(schemas: ["extra"], in: m.dir.url)
        await model.importFile(file)   // 假电脑没有 extra 包，最后会失败；但清单已经更新
        #expect(http.callCount(C.remote) == 1)
        #expect(model.catalogStatus.catalog.package("extra") != nil)
        #expect(env.catalog.package("extra") != nil)   // 引导和主窗口共用一份
    }

    @Test func 引导里导入时也会更新清单() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let env = m.environment(catalogHTTP: http, catalogKeys: [C.publicKey])
        let flow = SetupFlow(env: env)
        await flow.importFile(try C.exportFile(schemas: ["extra"], in: m.dir.url))
        #expect(env.catalog.package("extra") != nil)
    }

    @Test func 清单来源的说法() throws {
        let catalog = try Catalog.decode(C.json(serial: 7))
        #expect(NetworkUse.catalogSource(CatalogStatus(catalog: catalog, origin: .builtIn, cacheProblem: nil))
                == "现在用的是应用内置的方案清单（编号 7）")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NetworkUse.catalogSource(CatalogStatus(catalog: catalog, origin: .online(date), cacheProblem: nil))
                == "现在用的是在线方案清单（编号 7，\(date.formatted(date: .numeric, time: .omitted)) 下载）")
    }
}
