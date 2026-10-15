import Foundation

/// 网络访问。正式用 URLSessionHTTPClient，测试换成假的。
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
    func download(_ url: URL, to destination: URL) async throws
}

public enum HTTPError: Error, Equatable, Sendable, CustomStringConvertible {
    case status(Int, URL)
    case transport(String)

    /// 断网、服务器出错、请求太快可以重试；被拒绝（403，多半是 GitHub 限流）、找不到（404）不重试
    public var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .status(let code, _): return code == 429 || (500...599).contains(code)
        }
    }

    public var description: String {
        switch self {
        case .transport(let message):
            return "网络连接失败：\(message)"
        case .status(403, let url):
            return "GitHub 拒绝了请求（403），可能是一小时内访问次数超过了限制，请过一会儿再试：\(url.absoluteString)"
        case .status(404, let url):
            return "找不到（404）：\(url.absoluteString)"
        case .status(let code, let url):
            return "服务器返回错误 \(code)：\(url.absoluteString)"
        }
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request(url))
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        try check(response, url)
        return data
    }

    public func download(_ url: URL, to destination: URL) async throws {
        let (temp, response): (URL, URLResponse)
        do {
            (temp, response) = try await URLSession.shared.download(for: request(url))
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        try check(response, url)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("squirrel-macos", forHTTPHeaderField: "User-Agent")
        if url.host() == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private func check(_ response: URLResponse, _ url: URL) throws {
        guard let http = response as? HTTPURLResponse else { throw HTTPError.transport("不是 HTTP 响应") }
        guard http.statusCode == 200 else { throw HTTPError.status(http.statusCode, url) }
    }
}

public struct RetryPolicy: Sendable {
    public var attempts: Int
    public var delay: Duration

    public init(attempts: Int, delay: Duration) {
        self.attempts = attempts
        self.delay = delay
    }

    /// 正式使用：最多 3 次，每次间隔 2 秒
    public static let standard = RetryPolicy(attempts: 3, delay: .seconds(2))
    /// 测试用：最多 3 次，不等待
    public static let immediate = RetryPolicy(attempts: 3, delay: .zero)
}

/// 出错时按策略重试；不该重试的错误（HTTPError.isRetryable == false）马上抛出
func withRetry<T: Sendable>(_ policy: RetryPolicy, _ operation: @Sendable () async throws -> T) async throws -> T {
    var lastError: any Error = HTTPError.transport("没有尝试")
    for attempt in 1...max(1, policy.attempts) {
        do {
            return try await operation()
        } catch let error as HTTPError where !error.isRetryable {
            throw error
        } catch {
            lastError = error
            if attempt < policy.attempts { try await Task.sleep(for: policy.delay) }
        }
    }
    throw lastError
}
