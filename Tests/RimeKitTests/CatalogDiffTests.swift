import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogDiffTests {
    typealias C = TestCatalogs
    let addLua = (#""include":["*.schema.yaml","dicts/**"]"#, #""include":["*.schema.yaml","dicts/**","lua/**"]"#)

    func catalog(_ serial: Int, _ edits: [(String, String)] = []) throws -> Catalog {
        try Catalog.decode(C.json(serial: serial, edits))
    }

    @Test func 新增方案() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [C.extraPackage]), inUse: ["base"])
        #expect(diff.addedSchemas.map(\.id) == ["extra"])
        #expect(!diff.affectsInUse)
        #expect(diff.lines == ["新增方案：新方案"])
    }

    @Test func 在用的包规则变了() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [addLua]), inUse: ["base", "app"])
        #expect(diff.changedInUse == ["基础"])
        #expect(diff.affectsInUse)
        #expect(diff.lines == ["你在用的这些方案包的安装规则变了：基础。应用改动后生效"])
    }

    @Test func 没在用的包规则变了不算() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [addLua]), inUse: ["app"])
        #expect(!diff.affectsInUse)
    }

    @Test func 只改了说明文字不算规则变了() throws {
        let new = try catalog(2, [(#""name":"基础","summary":"s""#, #""name":"基础","summary":"新的说明""#)])
        let diff = CatalogDiff(old: try catalog(1), new: new, inUse: ["base"])
        #expect(!diff.affectsInUse)
        #expect(diff.lines == ["方案没有变化（只更新了说明文字等）"])
    }

    @Test func 新标下架() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [C.app(#""deprecated":true"#)]), inUse: ["app", "base"])
        #expect(diff.newlyDeprecated == ["应用"])
        #expect(!diff.affectsInUse)   // 下架不算规则变了
        #expect(diff.lines == ["这些方案包下架了（已经在用的照常能用）：应用"])
    }

    @Test func 下架包里的方案不算新增() throws {
        let extraDeprecated = (C.extraPackage.0, C.extraPackage.1.replacingOccurrences(
            of: #"{"id":"extra","name":"新方案包""#, with: #"{"id":"extra","deprecated":true,"name":"新方案包""#))
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [extraDeprecated]), inUse: [])
        #expect(diff.addedSchemas.isEmpty)
    }
}
