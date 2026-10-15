import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTests {
    func context(_ http: FakeHTTPClient, _ dir: TempDir, catalog: Catalog? = nil) -> (Rimectl.Context, Output) {
        let output = Output(echo: false)
        let fixed = catalog
        let ctx = Rimectl.Context(
            http: http,
            retry: .immediate,
            catalog: { try fixed ?? Fixtures.catalog() },
            defaultPaths: Fixtures.paths(dir),
            output: output)
        return (ctx, output)
    }

    @Test func catalog列出内置的包和方案() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir, catalog: try Catalog.builtIn())
        #expect(await Rimectl.run(["catalog"], ctx) == 0)
        #expect(out.text.contains("rime-ice"))
        #expect(out.text.contains("double_pinyin_flypy"))
        #expect(out.text.contains("GPL-3.0"))
    }

    @Test func fetch带上依赖并输出每个包() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, appSHA: "abc123")
        let (ctx, out) = context(http, dir)
        #expect(await Rimectl.run(["fetch", "app"], ctx) == 0)
        let lines = out.text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("base@2026-10-05T13:38:43Z"))
        #expect(lines[0].contains("3 个文件"))
        #expect(lines[1].hasPrefix("app@abc123"))
    }

    @Test func data_dir可以换数据目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let (ctx, _) = context(http, dir)
        let other = dir.url.appending(path: "other", directoryHint: .isDirectory)
        #expect(await Rimectl.run(["fetch", "--data-dir", other.path, "base"], ctx) == 0)
        #expect(PackageStore(paths: AppPaths(root: other), http: http).latestCached("base") != nil)
        #expect(PackageStore(paths: Fixtures.paths(dir), http: http).latestCached("base") == nil)
    }

    @Test func 断网时提示可以用旧版本() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "v1")
        let (ctx, out) = context(http, dir)
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 0)
        http.stub(Fixtures.baseReleaseURL, .failure(.transport("断网")))
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 1)
        #expect(out.text.contains("网络连接失败：断网"))
        #expect(out.text.contains("v1"))
        #expect(out.text.contains("--cache-only"))
    }

    @Test func cache_only只用本地缓存不联网() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "v1")
        let (ctx, out) = context(http, dir)
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 0)
        let callsBefore = http.callCount(Fixtures.baseReleaseURL)
        #expect(await Rimectl.run(["fetch", "--cache-only", "base"], ctx) == 0)
        #expect(http.callCount(Fixtures.baseReleaseURL) == callsBefore)
        #expect(out.text.split(separator: "\n").last?.hasPrefix("base@v1") == true)
    }

    @Test func cache_only但没有缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["fetch", "--cache-only", "base"], ctx) == 1)
        #expect(out.text.contains("base：本地没有缓存"))
    }

    @Test func 不认识的包() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["fetch", "nope"], ctx) == 1)
        #expect(out.text.contains("清单里没有这个包：nope"))
    }

    @Test func 用法不对() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run([], ctx) == 2)
        #expect(await Rimectl.run(["what"], ctx) == 2)
        #expect(await Rimectl.run(["fetch"], ctx) == 2)
        #expect(await Rimectl.run(["fetch", "--data-dir"], ctx) == 2)
        #expect(out.text.contains("用法"))
    }
}

@Suite struct RimectlDownloadFailureTests {
    @Test func 认证页返回网页时也提示可以用旧版本() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "v1")
        let (ctx, out) = RimectlTests().context(http, dir)
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 0)
        http.stub(Fixtures.baseReleaseURL, .success(Data("<html>请先登录 Wi-Fi</html>".utf8)))
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 1)
        #expect(out.text.contains("看不懂 GitHub 返回的内容"))
        #expect(out.text.contains("v1"))
        #expect(out.text.contains("--cache-only"))
    }

    @Test func 下载内容坏了也提示可以用旧版本() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "v1")
        let (ctx, out) = RimectlTests().context(http, dir)
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 0)
        try Fixtures.stubAll(http, baseVersion: "v2")
        http.stub(Fixtures.baseZipURL, .success(Data("不是 zip".utf8)))
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 1)
        #expect(out.text.contains("解压失败"))
        #expect(out.text.contains("--cache-only"))
    }

    @Test func 哪些错误算下载失败() {
        let url = URL(string: "https://example.com")!
        #expect(PackageStore.isDownloadFailure(HTTPError.transport("x")))
        #expect(PackageStore.isDownloadFailure(SourceError.badResponse(url)))
        #expect(PackageStore.isDownloadFailure(UnzipError.failed(status: 1, message: "x")))
        #expect(!PackageStore.isDownloadFailure(CatalogError.unknownPackage("x")))
        #expect(!PackageStore.isDownloadFailure(PackageStoreError.anchorNotFound(package: "x", anchor: "y")))
    }
}
