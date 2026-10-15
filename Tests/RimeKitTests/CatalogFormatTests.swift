import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogFormatTests {
    typealias C = TestCatalogs

    @Test func 旧清单没写的字段有默认值() throws {
        let c = try Fixtures.catalog()
        #expect(c.serial == 0)
        #expect(c.packages.allSatisfy { !$0.deprecated && $0.minAppVersion == nil })
    }

    @Test func 读出serial_下架_最低版本() throws {
        let c = try Catalog.decode(C.json(serial: 7, [C.app(#""deprecated":true,"minAppVersion":"0.3.0""#)]))
        #expect(c.serial == 7)
        #expect(c.package("app")?.deprecated == true)
        #expect(c.package("app")?.minAppVersion == "0.3.0")
        #expect(c.package("base")?.deprecated == false)
    }

    @Test func 最低版本写错了校验不过() {
        #expect(throws: CatalogError.badMinAppVersion(package: "app", value: "v1")) {
            try Catalog.decode(C.json(serial: 1, [C.app(#""minAppVersion":"v1""#)]))
        }
    }

    @Test func 版本号比较() throws {
        func v(_ s: String) throws -> AppVersion { try #require(AppVersion(s)) }
        #expect(try v("0.10.0") > v("0.9.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("0.3.0-rc1") == v("0.3.0"))
        #expect(try v("0.2.0") < v("0.3"))
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v1") == nil)
        #expect(AppVersion("1..0") == nil)
        #expect(AppVersion("+1.0") == nil)
    }

    @Test func 用不了的包和依赖它的包都去掉() throws {
        let c = try Catalog.decode(C.json(serial: 1, [C.base(#""minAppVersion":"9.0.0""#)]))
        let old = c.available(for: try #require(AppVersion("0.2.0")))
        #expect(old.packages.isEmpty)   // app 依赖 base，也去掉
        #expect(old.serial == 1)
        let new = c.available(for: try #require(AppVersion("9.0.0")))
        #expect(new.packages.map(\.id) == ["base", "app"])
    }

    @Test func 只去掉要求新版本的那个包() throws {
        let c = try Catalog.decode(C.json(serial: 1, [C.app(#""minAppVersion":"9.0.0""#)]))
        let available = c.available(for: try #require(AppVersion("0.2.0")))
        #expect(available.packages.map(\.id) == ["base"])
        try available.validate()
    }

    @Test func 选项里依赖的包被去掉时整个包也去掉() throws {
        let text = GenFixtures.catalogJSON.replacingOccurrences(
            of: #"{"id":"words","name":"词库""#, with: #"{"id":"words","minAppVersion":"9.0.0","name":"词库""#)
        let c = try Catalog.decode(Data(text.utf8))
        let ids = c.available(for: try #require(AppVersion("0.2.0"))).packages.map(\.id)
        #expect(ids == ["pinyin"])   // wubi 的「大词库」选项依赖 words
    }
}
