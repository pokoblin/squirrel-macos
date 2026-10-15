import Foundation
import Testing
@testable import RimeKit

@Suite struct PackageStoreTests {
    @Test func 没有顶层目录的zip按规则挑文件() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkg = try await store.fetch(try #require(try Fixtures.catalog().package("base")))

        #expect(pkg.info.id == "base")
        #expect(pkg.info.version == "2026-10-05T13:38:43Z")
        #expect(pkg.info.files == ["base.schema.yaml", "dicts/a.dict.yaml", "dicts/sub/b.dict.yaml"])
        #expect(pkg.info.zipSHA256.count == 64)
        let text = try String(contentsOf: pkg.filesDirectory.appending(path: "dicts/sub/b.dict.yaml"), encoding: .utf8)
        #expect(text == "b")
        #expect(!FileManager.default.fileExists(atPath: pkg.filesDirectory.appending(path: "README.md").path))
        #expect(!FileManager.default.fileExists(atPath: pkg.filesDirectory.appending(path: "dicts/skip.txt").path))
    }

    @Test func 有顶层目录的zip靠定位文件找到根目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, appSHA: "18a6016c")
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkg = try await store.fetch(try #require(try Fixtures.catalog().package("app")))
        #expect(pkg.info.version == "18a6016c")
        #expect(pkg.info.files == ["app.schema.yaml"])
        #expect(pkg.info.sourceURL == Fixtures.appZipURL("18a6016c"))
    }

    @Test func 版本号里的冒号不进目录名() {
        #expect(PackageStore.directoryName(id: "rime-ice", version: "2026-10-05T13:38:43Z") == "rime-ice@2026-10-05T13-38-43Z")
        #expect(PackageStore.directoryName(id: "x", version: "a/b c") == "x@a-b-c")
    }

    @Test func 已经缓存的版本不再下载() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let spec = try #require(try Fixtures.catalog().package("base"))
        let first = try await store.fetch(spec)
        let second = try await store.fetch(spec)
        #expect(first == second)
        #expect(http.callCount(Fixtures.baseZipURL) == 1)
        #expect(http.callCount(Fixtures.baseReleaseURL) == 2)   // 每次都要问最新版本
    }

    @Test func 缺必需文件时报错而且不留缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .success(try ZipFixture.make(["base.schema.yaml": "b"], topFolder: nil)))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        await #expect(throws: PackageStoreError.missingRequiredFiles(package: "base", files: ["dicts/a.dict.yaml"])) {
            try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        }
        #expect(store.cachedVersions("base").isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: Fixtures.paths(dir).packages.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func 找不到定位文件() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .success(try ZipFixture.make(["other.yaml": "x"], topFolder: "x")))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        await #expect(throws: PackageStoreError.anchorNotFound(package: "base", anchor: "base.schema.yaml")) {
            try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        }
    }

    @Test func 下载到一半断网不留缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .failure(.transport("断网")))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        await #expect(throws: HTTPError.transport("断网")) {
            try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        }
        #expect(http.callCount(Fixtures.baseZipURL) == 3)   // 重试过
        #expect(store.latestCached("base") == nil)
    }

    @Test func 没有package_json的残留目录不算缓存() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let half = paths.packages.appending(path: "base@v1/files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: half, withIntermediateDirectories: true)
        let store = PackageStore(paths: paths, http: FakeHTTPClient(), retry: .immediate)
        #expect(store.cached("base", version: "v1") == nil)
        #expect(store.cachedVersions("base").isEmpty)
    }

    @Test func zip里的符号链接不复制() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .success(try ZipFixture.make(
            ["base.schema.yaml": "b", "dicts/a.dict.yaml": "a"],
            topFolder: nil,
            symlinks: ["dicts/evil.dict.yaml": "/etc/hosts"])))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkg = try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        #expect(pkg.info.files == ["base.schema.yaml", "dicts/a.dict.yaml"])
        let evil = pkg.filesDirectory.appending(path: "dicts/evil.dict.yaml").path
        #expect((try? FileManager.default.attributesOfItem(atPath: evil)) == nil)
    }

    @Test func 新旧版本都保留而且最新取到的排前面() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let paths = Fixtures.paths(dir)
        let spec = try #require(try Fixtures.catalog().package("base"))

        try Fixtures.stubAll(http, baseVersion: "v1")
        let store = PackageStore(paths: paths, http: http, retry: .immediate, now: clock.next)
        _ = try await store.fetch(spec)
        try Fixtures.stubAll(http, baseVersion: "v2")
        _ = try await store.fetch(spec)

        #expect(store.cachedVersions("base").map(\.info.version) == ["v2", "v1"])
        #expect(store.latestCached("base")?.info.version == "v2")
        #expect(store.cached("base", version: "v1") != nil)
    }

    @Test func 一次取多个包时依赖在前() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkgs = try await store.fetchAll(["app"], catalog: try Fixtures.catalog())
        #expect(pkgs.map(\.info.id) == ["base", "app"])
    }

    @Test func 下载用的暂存目录用完就删() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let paths = Fixtures.paths(dir)
        let store = PackageStore(paths: paths, http: http, retry: .immediate)
        _ = try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        let left = (try? FileManager.default.contentsOfDirectory(atPath: paths.staging.path)) ?? []
        #expect(left.isEmpty)
    }
}

/// 每次调用往后走一秒的假时钟，让「谁先取到」有确定的顺序
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) { current = start }

    var next: @Sendable () -> Date {
        { [self] in
            lock.withLock {
                current = current.addingTimeInterval(1)
                return current
            }
        }
    }
}

@Suite struct PackageStoreCacheRulesTests {
    @Test func 清单规则变了就不用旧缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let old = try #require(try Fixtures.catalog().package("base"))
        _ = try await store.fetch(old)

        let json = Fixtures.catalogJSON
            .replacingOccurrences(of: #""include":["*.schema.yaml","dicts/**"]"#, with: #""include":["*.schema.yaml","dicts/**","README.md"]"#)
            .replacingOccurrences(of: #""requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"]"#, with: #""requiredFiles":["base.schema.yaml","dicts/a.dict.yaml","README.md"]"#)
        let newer = try #require(try Catalog.decode(Data(json.utf8)).package("base"))
        #expect(newer != old)
        #expect(store.latestCached(for: newer) == nil)
        let pkg = try await store.fetch(newer)
        #expect(pkg.info.files.contains("README.md"))
        #expect(http.callCount(Fixtures.baseZipURL) == 2)
        #expect(store.latestCached(for: newer)?.info.files.contains("README.md") == true)
        #expect(store.latestCached(for: old) == nil)   // 同一版本被新规则的缓存替换了
    }

    @Test func 目录名一样但版本不同不算命中() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "a:b")
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        _ = try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        #expect(store.cached("base", version: "a:b") != nil)
        #expect(store.cached("base", version: "a-b") == nil)
    }

    @Test func 找包根目录按目录层数取最浅的() {
        #expect(PackageStore.locateRoot(in: ["abcdefgh/x.yaml", "a/b/x.yaml"], anchor: "x.yaml") == "abcdefgh/")
    }
}
