import Foundation

public struct SquirrelRelease: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL
    /// GitHub 给的 sha256（小写十六进制）；接口没给时为空
    public let sha256: String?

    public init(version: String, downloadURL: URL, sha256: String?) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
    }
}

public enum SquirrelReleaseError: Error, Equatable, Sendable, CustomStringConvertible {
    case noPackage
    case badResponse

    public var description: String {
        switch self {
        case .noPackage: return "鼠须管最新的发布里找不到安装包（Squirrel-*.pkg）"
        case .badResponse: return "看不懂 GitHub 返回的鼠须管发布信息"
        }
    }
}

/// 从 GitHub 取鼠须管最新的正式版本
public struct SquirrelReleaseSource: Sendable {
    public static let latestURL = URL(string: "https://api.github.com/repos/rime/squirrel/releases/latest")!

    let http: any HTTPClient
    let retry: RetryPolicy

    public init(http: any HTTPClient, retry: RetryPolicy = .standard) {
        self.http = http
        self.retry = retry
    }

    public func latest() async throws -> SquirrelRelease {
        let http = self.http
        let url = Self.latestURL
        let data = try await withRetry(retry) { try await http.get(url) }
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw SquirrelReleaseError.badResponse
        }
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Squirrel-") && $0.name.hasSuffix(".pkg") }) else {
            throw SquirrelReleaseError.noPackage
        }
        let sha = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        return SquirrelRelease(version: release.tagName, downloadURL: asset.downloadURL, sha256: sha)
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: URL
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name, digest
                case downloadURL = "browser_download_url"
            }
        }
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case assets
            case tagName = "tag_name"
        }
    }
}
