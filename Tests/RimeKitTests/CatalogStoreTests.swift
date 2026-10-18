import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogStoreTests {
    typealias C = TestCatalogs

    func cacheExists(_ paths: AppPaths) -> Bool {
        FileManager.default.fileExists(atPath: paths.catalogCache.appending(path: "catalog.json").path)
    }

    // MARK: 生效的清单

    @Test func 没有缓存时用内置的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let status = try C.store(Fixtures.paths(dir)).effective()
        #expect(status.origin == .builtIn)
        #expect(status.catalog.serial == 10)
        #expect(status.cacheProblem == nil)
    }

    @Test func 缓存更新就用缓存() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11, [C.extraPackage]))
        let status = try C.store(paths).effective()
        guard case .online = status.origin else { Issue.record("应该用缓存：\(status.origin)"); return }
        #expect(status.catalog.serial == 11)
        #expect(status.catalog.package("extra") != nil)
    }

    @Test(arguments: [10, 9])
    func 缓存不比内置的新就用内置的(serial: Int) throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: serial))
        let status = try C.store(paths).effective()
        #expect(status.origin == .builtIn)
        #expect(status.cacheProblem == nil)
    }

    @Test func 缓存签名不对时用内置的并说明原因() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11), signature: C.sign(Data("别的内容".utf8)))
        let status = try C.store(paths).effective()
        #expect(status.origin == .builtIn)
        #expect(status.cacheProblem == "缓存的方案清单签名不对")
    }

    @Test func 缓存只剩一个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11))
        try FileManager.default.removeItem(at: paths.catalogCache.appending(path: "catalog.json.sig"))
        let status = try C.store(paths).effective()
        #expect(status.origin == .builtIn)
        #expect(status.cacheProblem == "缓存的方案清单不完整")
    }

    @Test func 当前应用用不了的包不出现() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let builtIn = C.json(serial: 10, [C.app(#""minAppVersion":"9.0.0""#)])
        let status = try C.store(Fixtures.paths(dir), builtIn: builtIn).effective()
        #expect(status.catalog.packages.map(\.id) == ["base"])
    }

    // MARK: 检查更新

    @Test func 有更新就采用并写进缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let store = C.store(paths, http)
        let result = await store.check(inUse: Settings(schemas: ["base"]))
        guard case .updated(let diff, let status) = result else { Issue.record("\(result)"); return }
        #expect(diff.addedSchemas.map(\.id) == ["extra"])
        #expect(status.catalog.serial == 11)
        guard case .online = status.origin else { Issue.record("\(status.origin)"); return }
        #expect(try store.effective().catalog.serial == 11)
    }

    @Test func 不比手头的新就不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 10))
        #expect(await C.store(paths, http).check(inUse: nil) == .upToDate)
        #expect(!cacheExists(paths))
    }

    @Test func 签名不对不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11), signature: C.sign(Data("别的内容".utf8)))
        #expect(await C.store(paths, http).check(inUse: nil) == .rejected("方案清单的签名不对，没有采用。如果方案清单刚发布不久，GitHub 可能还在给旧文件，过几分钟再试"))
        #expect(!cacheExists(paths))
    }

    @Test func 连不上() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let result = await C.store(Fixtures.paths(dir), FakeHTTPClient()).check(inUse: nil)
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.hasPrefix("没拉到方案清单："))
    }

    @Test func 格式不对() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, Data("{}".utf8))
        let result = await C.store(Fixtures.paths(dir), http).check(inUse: nil)
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.hasPrefix("方案清单读不了："))
    }

    @Test func 格式版本太新不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        let newer = String(decoding: C.json(serial: 11), as: UTF8.self)
            .replacingOccurrences(of: #""formatVersion":1"#, with: #""formatVersion":2"#)
        C.serve(http, Data(newer.utf8))
        let result = await C.store(paths, http).check(inUse: nil)
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.contains("请更新应用"))
        #expect(!cacheExists(paths))
    }

    @Test func 和正在用的设置对不上就不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.app(#""minAppVersion":"9.0.0""#)]))
        let store = C.store(paths, http)
        let result = await store.check(inUse: Settings(schemas: ["app"]))
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.contains("和你现在的设置对不上"))
        #expect(!cacheExists(paths))
        #expect(try store.effective().catalog.serial == 10)
    }

    @Test func 旧缓存被替换() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11))
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 12))
        let store = C.store(paths, http)
        guard case .updated = await store.check(inUse: nil) else { Issue.record("应该更新"); return }
        #expect(try store.effective().catalog.serial == 12)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.catalogCache.path).sorted() == ["catalog.json", "catalog.json.sig"])
    }

    @Test(arguments: [11, 10])
    func 缓存比内置新时_拉到不比缓存新的不采用(fetched: Int) async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11))
        let cacheFile = paths.catalogCache.appending(path: "catalog.json")
        let before = try Data(contentsOf: cacheFile)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: fetched))
        let store = C.store(paths, http)
        #expect(await store.check(inUse: nil) == .upToDate)
        #expect(try store.effective().catalog.serial == 11)
        #expect(try Data(contentsOf: cacheFile) == before)
    }

    @Test func 检查被拒时旧缓存不动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11))
        let cacheFile = paths.catalogCache.appending(path: "catalog.json")
        let before = try Data(contentsOf: cacheFile)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 12), signature: C.sign(Data("别的".utf8)))
        let store = C.store(paths, http)
        guard case .rejected = await store.check(inUse: nil) else { Issue.record("应该被拒"); return }
        #expect(try store.effective().catalog.serial == 11)
        #expect(try Data(contentsOf: cacheFile) == before)
    }

    @Test func 签名地址在清单旁边() {
        #expect(CatalogStore.signatureURL(C.remote).absoluteString == "https://example.com/catalog/v1/catalog.json.sig")
        #expect(CatalogStore.defaultRemote.absoluteString == "https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json")
    }
}
