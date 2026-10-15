import Foundation
import Testing
@testable import RimeKit

/// 真的去 GitHub 下载内置清单里的包，检查上游结构没变。默认不跑：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1"))
struct OnlineTests {
    @Test(arguments: (try? Catalog.builtIn().packages.map(\.id)) ?? [])
    func 真实下载内置清单里的包(id: String) async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let catalog = try Catalog.builtIn()
        let spec = try #require(catalog.package(id))
        let store = PackageStore(paths: Fixtures.paths(dir))
        let pkg = try await store.fetch(spec)
        for file in spec.requiredFiles {
            #expect(pkg.info.files.contains(file), "缺少 \(file)")
        }
        #expect(!pkg.info.version.isEmpty)
    }

    @Test func 在线方案清单签名正确而且不比内置的旧() async throws {
        let http = URLSessionHTTPClient()
        let data = try await http.get(CatalogStore.defaultRemote)
        let signature = try await http.get(CatalogStore.signatureURL(CatalogStore.defaultRemote))
        #expect(CatalogSignature.verify(data, signature: signature, keys: CatalogSignature.trustedKeys))
        #expect(try Catalog.decode(data).serial >= Catalog.builtIn().serial)
    }
}
