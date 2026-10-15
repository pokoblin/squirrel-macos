import Foundation
@testable import RimeKit

/// 假的网络：每个地址按顺序返回事先设置好的结果，最后一个结果一直重复
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: [Result<Data, HTTPError>]] = [:]
    private var calls: [URL: Int] = [:]

    func stub(_ url: URL, _ results: Result<Data, HTTPError>...) {
        lock.withLock { responses[url] = results }
    }

    func callCount(_ url: URL) -> Int {
        lock.withLock { calls[url, default: 0] }
    }

    func get(_ url: URL) async throws -> Data {
        try next(url)
    }

    func download(_ url: URL, to destination: URL) async throws {
        let data = try next(url)
        try data.write(to: destination)
    }

    private func next(_ url: URL) throws -> Data {
        let result: Result<Data, HTTPError> = lock.withLock {
            let n = calls[url, default: 0]
            calls[url] = n + 1
            guard let list = responses[url], !list.isEmpty else { return .failure(.status(404, url)) }
            return list[min(n, list.count - 1)]
        }
        return try result.get()
    }
}
