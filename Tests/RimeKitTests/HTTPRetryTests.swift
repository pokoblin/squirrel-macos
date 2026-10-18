import Foundation
import Testing
@testable import RimeKit

@Suite struct HTTPRetryTests {
    let url = URL(string: "https://example.com/x")!

    @Test func 断网两次第三次成功() async throws {
        let http = FakeHTTPClient()
        http.stub(url, .failure(.transport("断网")), .failure(.transport("断网")), .success(Data("ok".utf8)))
        let data = try await withRetry(.immediate) { try await http.get(url) }
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(http.callCount(url) == 3)
    }

    @Test func 重试次数用完就放弃() async {
        let http = FakeHTTPClient()
        http.stub(url, .failure(.status(503, url)))
        await #expect(throws: HTTPError.status(503, url)) {
            try await withRetry(.immediate) { try await http.get(url) }
        }
        #expect(http.callCount(url) == 3)
    }

    @Test func 限流和找不到不重试() async {
        let http = FakeHTTPClient()
        http.stub(url, .failure(.status(403, url)))
        await #expect(throws: HTTPError.status(403, url)) {
            try await withRetry(.immediate) { try await http.get(url) }
        }
        #expect(http.callCount(url) == 1)
    }

    @Test func 哪些错误可以重试() {
        #expect(HTTPError.transport("x").isRetryable)
        #expect(HTTPError.status(500, url).isRetryable)
        #expect(HTTPError.status(429, url).isRetryable)
        #expect(!HTTPError.status(403, url).isRetryable)
        #expect(!HTTPError.status(404, url).isRetryable)
    }

    @Test func 错误信息是中文() {
        #expect(HTTPError.status(403, url).description.contains("403"))
        #expect(HTTPError.status(403, url).description.contains("限制"))
        #expect(HTTPError.transport("超时").description == "网络连接失败：超时")
    }

    @Test func 请求太频繁时说过一会儿再试() {
        #expect(HTTPError.status(429, URL(string: "https://example.com")!).description.contains("过一会儿再试"))
    }

}

/// 方案清单和签名是两个文件：本地缓存可能给出新清单配旧签名，误报「签名不对」。raw.githubusercontent.com 的请求不用本地缓存
@Suite struct HTTPRequestCacheTests {
    @Test func 方案清单的请求不用本地缓存() {
        let raw = URLSessionHTTPClient.request(URL(string: "https://raw.githubusercontent.com/o/r/main/catalog/v1/catalog.json")!)
        #expect(raw.cachePolicy == .reloadIgnoringLocalCacheData)
        let api = URLSessionHTTPClient.request(URL(string: "https://api.github.com/repos/o/r/commits/main")!)
        #expect(api.cachePolicy == .useProtocolCachePolicy)
        #expect(api.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }
}
