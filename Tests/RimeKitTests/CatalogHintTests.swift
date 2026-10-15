import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@Suite struct CatalogHintTests {
    @Test(arguments: [
        PackageStoreError.missingRequiredFiles(package: "p", files: ["a"]).description,
        PackageStoreError.anchorNotFound(package: "p", anchor: "a").description,
        SourceError.assetNotFound(repo: "o/r", tag: "t", asset: "a.zip").description,
    ])
    func 上游变了时先建议检查清单更新(text: String) {
        #expect(text.contains("rimectl catalog check"))
        #expect(text.hasSuffix("还不行的话，请更新应用"))
        let app = AppWording.forApp(text)
        #expect(app.contains("可以先到「方案」页点「检查方案清单更新」"))
        #expect(!app.contains("rimectl"))
    }
}
