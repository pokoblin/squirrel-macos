import Foundation

/// 缓存里一个包的说明，存成 packages/<id>@<版本>/package.json
public struct PackageInfo: Sendable, Equatable, Codable {
    public let id: String
    public let version: String
    public let sourceURL: URL
    public let zipSHA256: String
    public let fetchedAt: Date
    /// 装进来的文件（相对包根目录），已排序
    public let files: [String]
}

public struct CachedPackage: Sendable, Equatable {
    public let info: PackageInfo
    /// 文件所在目录：packages/<id>@<版本>/files
    public let filesDirectory: URL
}

public enum PackageStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case anchorNotFound(package: String, anchor: String)
    case missingRequiredFiles(package: String, files: [String])

    public var description: String {
        switch self {
        case let .anchorNotFound(package, anchor):
            return "\(package) 的下载内容里找不到 \(anchor)，上游方案目录结构变了，需要更新应用"
        case let .missingRequiredFiles(package, files):
            return "\(package) 的下载内容里缺少这些文件：\(files.joined(separator: "、"))。上游方案目录结构变了，需要更新应用"
        }
    }
}

/// 上游包的下载和缓存（设计第 3、5 节）。
/// 先在暂存区做好一个完整的包（最后写 package.json），再整体移进 packages/，
/// 所以中途失败不会留下看起来像缓存的半成品。
public struct PackageStore: Sendable {
    public let paths: AppPaths
    let http: any HTTPClient
    let retry: RetryPolicy
    let resolver: SourceResolver
    let now: @Sendable () -> Date

    public init(
        paths: AppPaths,
        http: any HTTPClient = URLSessionHTTPClient(),
        retry: RetryPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.http = http
        self.retry = retry
        self.resolver = SourceResolver(http: http, retry: retry)
        self.now = now
    }

    /// 缓存目录名：<id>@<版本>，版本里不安全的字符换成 "-"
    public static func directoryName(id: String, version: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let safe = String(version.map { allowed.contains($0) ? $0 : "-" })
        return "\(id)@\(safe)"
    }

    public func cached(_ id: String, version: String) -> CachedPackage? {
        load(paths.packages.appending(path: Self.directoryName(id: id, version: version), directoryHint: .isDirectory), id: id)
    }

    /// 本地缓存的所有版本，最新取到的在前
    public func cachedVersions(_ id: String) -> [CachedPackage] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.packages.path)) ?? []
        return names
            .filter { $0.hasPrefix("\(id)@") }
            .compactMap { load(paths.packages.appending(path: $0, directoryHint: .isDirectory), id: id) }
            .sorted { $0.info.fetchedAt > $1.info.fetchedAt }
    }

    public func latestCached(_ id: String) -> CachedPackage? {
        cachedVersions(id).first
    }

    /// 取这个包的最新版：本地已有这个版本就直接用，没有就下载
    public func fetch(_ spec: PackageSpec) async throws -> CachedPackage {
        let resolved = try await resolver.resolve(spec.source)
        if let hit = cached(spec.id, version: resolved.version) { return hit }

        let fm = FileManager.default
        let work = paths.staging.appending(path: "fetch-\(spec.id)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zip = work.appending(path: "download.zip")
        let http = self.http
        try await withRetry(retry) { try await http.download(resolved.downloadURL, to: zip) }
        let sha = try Hashing.sha256(of: zip)

        let extracted = work.appending(path: "extracted", directoryHint: .isDirectory)
        try Unzipper().unzip(zip, into: extracted)
        let all = try fm.subpathsOfDirectory(atPath: extracted.path)
        guard let root = Self.locateRoot(in: all, anchor: spec.anchor) else {
            throw PackageStoreError.anchorNotFound(package: spec.id, anchor: spec.anchor)
        }

        let staged = work.appending(path: "package", directoryHint: .isDirectory)
        let filesDir = staged.appending(path: "files", directoryHint: .isDirectory)
        let copied = try Self.copySelected(from: extracted, subpaths: all, root: root, to: filesDir, spec: spec)
        let missing = spec.requiredFiles.filter { !copied.contains($0) }
        guard missing.isEmpty else {
            throw PackageStoreError.missingRequiredFiles(package: spec.id, files: missing)
        }

        let info = PackageInfo(id: spec.id, version: resolved.version, sourceURL: resolved.downloadURL,
                               zipSHA256: sha, fetchedAt: now(), files: copied.sorted())
        try JSONCoding.encoder.encode(info).write(to: staged.appending(path: "package.json"))

        try fm.createDirectory(at: paths.packages, withIntermediateDirectories: true)
        let destination = paths.packages.appending(path: Self.directoryName(id: spec.id, version: resolved.version), directoryHint: .isDirectory)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }   // 没有 package.json 的残留
        try fm.moveItem(at: staged, to: destination)
        // 从磁盘再读一次再返回：JSON 里的时间只精确到秒，这样和以后从缓存读出来的完全一样
        guard let saved = load(destination, id: spec.id) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: destination.path])
        }
        return saved
    }

    /// 取多个包（自动带上依赖，依赖在前）
    public func fetchAll(_ ids: [String], catalog: Catalog) async throws -> [CachedPackage] {
        var result: [CachedPackage] = []
        for spec in try catalog.installOrder(for: ids) {
            result.append(try await fetch(spec))
        }
        return result
    }

    // MARK: 内部

    private func load(_ directory: URL, id: String) -> CachedPackage? {
        guard let data = try? Data(contentsOf: directory.appending(path: "package.json")),
              let info = try? JSONCoding.decoder.decode(PackageInfo.self, from: data),
              info.id == id
        else { return nil }
        return CachedPackage(info: info, filesDirectory: directory.appending(path: "files", directoryHint: .isDirectory))
    }

    /// 找包根目录：哪个目录下有 anchor 这个相对路径的文件。返回 "" 或 "xxx/" 这样的前缀，取最浅的。
    static func locateRoot(in subpaths: [String], anchor: String) -> String? {
        subpaths
            .filter { $0 == anchor || $0.hasSuffix("/" + anchor) }
            .map { String($0.dropLast(anchor.count)) }
            .min { $0.count < $1.count }
    }

    /// 按安装规则把根目录下的普通文件复制出来；符号链接、目录都跳过。返回复制了的相对路径。
    static func copySelected(from extracted: URL, subpaths: [String], root: String, to filesDir: URL, spec: PackageSpec) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        var copied: [String] = []
        for sub in subpaths where sub.hasPrefix(root) {
            let relative = String(sub.dropFirst(root.count))
            guard !relative.isEmpty,
                  spec.include.contains(where: { $0.matches(relative) }),
                  !spec.exclude.contains(where: { $0.matches(relative) })
            else { continue }
            let source = extracted.appending(path: sub)
            let type = try fm.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
            guard type == .typeRegular else { continue }
            let target = filesDir.appending(path: relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            copied.append(relative)
        }
        return copied
    }
}
