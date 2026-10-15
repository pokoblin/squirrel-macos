import Foundation

public enum InstallOutcome: Sendable, Equatable {
    /// 已经装了同版本或更新的版本，没动
    case alreadyInstalled(String)
    case installed(String, previous: String?)
}

/// 下载、检查、安装鼠须管（设计 6.2 第 1 步）
public struct SquirrelInstaller: Sendable {
    let paths: AppPaths
    let locations: RimeLocations
    let http: any HTTPClient
    let retry: RetryPolicy
    let verifier: any PackageVerifying
    let privileged: any PrivilegedInstalling

    public init(paths: AppPaths, locations: RimeLocations, http: any HTTPClient, retry: RetryPolicy = .standard,
                verifier: any PackageVerifying = SquirrelPackageVerifier(), privileged: any PrivilegedInstalling) {
        self.paths = paths
        self.locations = locations
        self.http = http
        self.retry = retry
        self.verifier = verifier
        self.privileged = privileged
    }

    public func install(force: Bool = false) async throws -> InstallOutcome {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let current = locations.installedSquirrelVersion
        let release = try await SquirrelReleaseSource(http: http, retry: retry).latest()
        if !force, let current, Self.isUpToDate(current: current, latest: release.version) {
            return .alreadyInstalled(current)
        }

        let fm = FileManager.default
        let work = paths.staging.appending(path: "install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        // 文件名固定：版本号里可能有 / 之类的字符
        let pkg = work.appending(path: "Squirrel.pkg")
        let http = self.http
        try await withRetry(retry) { try await http.download(release.downloadURL, to: pkg) }
        try verifier.verify(pkg, sha256: release.sha256)
        try await privileged.installPackage(pkg, sha256: release.sha256)

        let after = locations.installedSquirrelVersion
        guard let after, Self.sameVersion(after, release.version) else {
            throw InstallError.versionMismatch(expected: release.version, found: after)
        }
        return .installed(after, previous: current)
    }

    /// 版本号都是数字时按数字比；认不出（rc、beta 等）时按原文比是否相同
    static func isUpToDate(current: String, latest: String) -> Bool {
        if let have = SquirrelVersion(current), let new = SquirrelVersion(latest) { return have >= new }
        return trimmed(current) == trimmed(latest)
    }

    static func sameVersion(_ a: String, _ b: String) -> Bool {
        if let x = SquirrelVersion(a), let y = SquirrelVersion(b) { return x == y }
        return trimmed(a) == trimmed(b)
    }

    static func trimmed(_ v: String) -> String { v.hasPrefix("v") ? String(v.dropFirst()) : v }
}
