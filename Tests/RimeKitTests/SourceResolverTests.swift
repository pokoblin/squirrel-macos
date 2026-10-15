import Foundation
import Testing
@testable import RimeKit

@Suite struct SourceResolverTests {
    @Test func Release附件用更新时间当版本() async throws {
        let http = FakeHTTPClient()
        http.stub(Fixtures.baseReleaseURL, .success(Fixtures.releaseJSON(assets: [
            ("other.zip", URL(string: "https://example.com/other.zip")!, "2020-01-01T00:00:00Z"),
            ("base.zip", Fixtures.baseZipURL, "2026-10-05T13:38:43Z"),
        ])))
        let resolver = SourceResolver(http: http, retry: .immediate)
        let r = try await resolver.resolve(.githubReleaseAsset(repo: "o/base", tag: "t", asset: "base.zip"))
        #expect(r == ResolvedSource(version: "2026-10-05T13:38:43Z", downloadURL: Fixtures.baseZipURL))
    }

    @Test func Release里没有这个附件() async {
        let http = FakeHTTPClient()
        http.stub(Fixtures.baseReleaseURL, .success(Fixtures.releaseJSON(assets: [])))
        let resolver = SourceResolver(http: http, retry: .immediate)
        await #expect(throws: SourceError.assetNotFound(repo: "o/base", tag: "t", asset: "base.zip")) {
            try await resolver.resolve(.githubReleaseAsset(repo: "o/base", tag: "t", asset: "base.zip"))
        }
    }

    @Test func 分支用提交号当版本并按提交号下载() async throws {
        let http = FakeHTTPClient()
        http.stub(Fixtures.appCommitURL, .success(Fixtures.commitJSON(sha: "18a6016c")))
        let resolver = SourceResolver(http: http, retry: .immediate)
        let r = try await resolver.resolve(.githubBranch(repo: "o/app", branch: "main"))
        #expect(r == ResolvedSource(version: "18a6016c", downloadURL: Fixtures.appZipURL("18a6016c")))
    }

    @Test func 被GitHub限流时报HTTP错误而不是解析错误() async {
        let http = FakeHTTPClient()
        http.stub(Fixtures.appCommitURL, .failure(.status(403, Fixtures.appCommitURL)))
        let resolver = SourceResolver(http: http, retry: .immediate)
        await #expect(throws: HTTPError.status(403, Fixtures.appCommitURL)) {
            try await resolver.resolve(.githubBranch(repo: "o/app", branch: "main"))
        }
    }

    @Test func 返回内容看不懂() async {
        let http = FakeHTTPClient()
        http.stub(Fixtures.appCommitURL, .success(Data("<html>".utf8)))
        let resolver = SourceResolver(http: http, retry: .immediate)
        await #expect(throws: SourceError.badResponse(Fixtures.appCommitURL)) {
            try await resolver.resolve(.githubBranch(repo: "o/app", branch: "main"))
        }
    }
}
