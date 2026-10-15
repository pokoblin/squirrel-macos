import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogPublishCheckTests {
    typealias C = TestCatalogs

    func catalog(_ serial: Int, _ edits: [(String, String)] = []) throws -> Catalog {
        try Catalog.decode(C.json(serial: serial, edits))
    }

    @Test func 第一次发布只要有serial() throws {
        #expect(CatalogPublishCheck.problems(old: nil, new: try catalog(1)).isEmpty)
        #expect(CatalogPublishCheck.problems(old: nil, new: try catalog(0)) == ["清单要写 serial（正整数，例如 2026101501）"])
    }

    @Test func serial要变大() throws {
        #expect(CatalogPublishCheck.problems(old: try catalog(5), new: try catalog(5)) == ["serial 要比上次发布的 5 大"])
        #expect(CatalogPublishCheck.problems(old: try catalog(5), new: try catalog(6)).isEmpty)
    }

    @Test func 加包没问题_删包不行() throws {
        #expect(CatalogPublishCheck.problems(old: try catalog(1), new: try catalog(2, [C.extraPackage])).isEmpty)
        let problems = CatalogPublishCheck.problems(old: try catalog(1, [C.extraPackage]), new: try catalog(2))
        #expect(problems == ["包 extra 不见了：已经发布的包不能删，要下架请标 deprecated",
                             "方案 extra 不见了：已经发布的方案不能删、不能改 id"])
    }

    @Test func 方案改id不行() throws {
        let renamed = try catalog(2, [(#"{"id":"app","name":"应用","category":"wubi"}"#, #"{"id":"app2","name":"应用","category":"wubi"}"#)])
        #expect(CatalogPublishCheck.problems(old: try catalog(1), new: renamed) == ["方案 app 不见了：已经发布的方案不能删、不能改 id"])
    }
}
