import Foundation

public struct ResolvedSource: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL

    public init(version: String, downloadURL: URL) {
        self.version = version
        self.downloadURL = downloadURL
    }
}

public enum SourceError: Error, Equatable, Sendable, CustomStringConvertible {
    case assetNotFound(repo: String, tag: String, asset: String)
    case badResponse(URL)

    public var description: String {
        switch self {
        case let .assetNotFound(repo, tag, asset):
            return "GitHub 上 \(repo) 的 \(tag) 版本里找不到 \(asset)，上游可能改了发布方式，需要更新应用"
        case .badResponse(let url):
            return "看不懂 GitHub 返回的内容：\(url.absoluteString)"
        }
    }
}

/// 问 GitHub：这个包现在的最新版本是什么、从哪下载
public struct SourceResolver: Sendable {
    let http: any HTTPClient
    let retry: RetryPolicy

    public init(http: any HTTPClient, retry: RetryPolicy = .standard) {
        self.http = http
        self.retry = retry
    }

    public func resolve(_ source: PackageSource) async throws -> ResolvedSource {
        switch source {
        case let .githubReleaseAsset(repo, tag, asset):
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
            let release: Release = try await fetchJSON(url)
            guard let found = release.assets.first(where: { $0.name == asset }) else {
                throw SourceError.assetNotFound(repo: repo, tag: tag, asset: asset)
            }
            return ResolvedSource(version: found.updatedAt, downloadURL: found.downloadURL)

        case let .githubBranch(repo, branch):
            let url = URL(string: "https://api.github.com/repos/\(repo)/commits/\(branch)")!
            let commit: Commit = try await fetchJSON(url)
            return ResolvedSource(
                version: commit.sha,
                downloadURL: URL(string: "https://codeload.github.com/\(repo)/zip/\(commit.sha)")!)
        }
    }

    private func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        let http = self.http
        let data = try await withRetry(retry) { try await http.get(url) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.badResponse(url)
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: URL
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
                case updatedAt = "updated_at"
            }
        }
        let assets: [Asset]
    }

    private struct Commit: Decodable {
        let sha: String
    }
}
