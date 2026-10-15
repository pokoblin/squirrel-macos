import Foundation

/// 现在用的是哪份方案清单
public enum CatalogOrigin: Sendable, Equatable {
    case builtIn
    /// 在线拉到的；日期是下载并采用的时间（缓存文件的修改时间）
    case online(Date)
}

public struct CatalogStatus: Sendable, Equatable {
    /// 生效的清单（已经去掉这个版本的应用用不了的包）
    public let catalog: Catalog
    public let origin: CatalogOrigin
    /// 缓存的在线清单用不了的原因（没有缓存、或缓存正常时为 nil）
    public let cacheProblem: String?

    public init(catalog: Catalog, origin: CatalogOrigin, cacheProblem: String?) {
        self.catalog = catalog
        self.origin = origin
        self.cacheProblem = cacheProblem
    }
}

public enum CatalogCheckResult: Sendable, Equatable {
    case upToDate
    case updated(CatalogDiff, CatalogStatus)
    /// 没用上，继续用手头那份；原因给人看
    case rejected(String)
}

/// 方案清单：内置的和在线拉到的哪份生效；检查在线更新（在线方案清单设计第 4 节）
public struct CatalogStore: Sendable {
    /// 在线清单的地址（路径里带格式版本）；debug 编译时可以用环境变量 RIMEKIT_CATALOG_URL 换掉（测试机实测用）
    public static var defaultRemote: URL {
        #if DEBUG
        if let text = ProcessInfo.processInfo.environment["RIMEKIT_CATALOG_URL"], let url = URL(string: text) { return url }
        #endif
        return URL(string: "https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v\(Catalog.supportedFormatVersion)/catalog.json")!
    }

    /// 签名文件和清单在同一目录：catalog.json.sig
    public static func signatureURL(_ remote: URL) -> URL {
        URL(string: remote.absoluteString + ".sig")!
    }

    public let paths: AppPaths
    let http: any HTTPClient
    let retry: RetryPolicy
    let builtIn: @Sendable () throws -> Catalog
    let keys: [Data]
    let remote: URL
    let appVersion: AppVersion

    public init(
        paths: AppPaths,
        http: any HTTPClient = URLSessionHTTPClient(),
        retry: RetryPolicy = .standard,
        builtIn: @escaping @Sendable () throws -> Catalog = { try Catalog.builtIn() },
        keys: [Data] = CatalogSignature.trustedKeys,
        remote: URL = CatalogStore.defaultRemote,
        appVersion: AppVersion = .current
    ) {
        self.paths = paths
        self.http = http
        self.retry = retry
        self.builtIn = builtIn
        self.keys = keys
        self.remote = remote
        self.appVersion = appVersion
    }

    var cacheFile: URL { paths.catalogCache.appending(path: "catalog.json") }
    var signatureFile: URL { paths.catalogCache.appending(path: "catalog.json.sig") }

    /// 生效的清单（设计 4.1）：内置的和缓存的，serial 大的那份（一样大用内置的）。
    /// 缓存每次都重新验签名，用不了就退回内置的并说明原因。只有内置的读不了才抛错
    public func effective() throws -> CatalogStatus {
        let builtIn = try self.builtIn()
        var chosen = builtIn
        var origin = CatalogOrigin.builtIn
        var problem: String?
        switch loadCache() {
        case .none:
            break
        case .broken(let reason):
            problem = reason
        case .ok(let cached, let date):
            if cached.serial > builtIn.serial {
                chosen = cached
                origin = .online(date)
            }
        }
        return CatalogStatus(catalog: chosen.available(for: appVersion), origin: origin, cacheProblem: problem)
    }

    enum Cached {
        case none
        case broken(String)
        case ok(Catalog, Date)
    }

    func loadCache() -> Cached {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheFile.path) || fm.fileExists(atPath: signatureFile.path) else { return .none }
        guard let data = try? Data(contentsOf: cacheFile), let signature = try? Data(contentsOf: signatureFile) else {
            return .broken("缓存的方案清单不完整")
        }
        guard CatalogSignature.verify(data, signature: signature, keys: keys) else {
            return .broken("缓存的方案清单签名不对")
        }
        do {
            let catalog = try Catalog.decode(data)
            let date = (try? fm.attributesOfItem(atPath: cacheFile.path))?[.modificationDate] as? Date ?? .distantPast
            return .ok(catalog, date)
        } catch {
            return .broken("缓存的方案清单读不了：\(error)")
        }
    }

    /// 检查在线更新（设计 4.2、4.3）：拉清单和签名 → 验签名 → 解析校验 → 比 serial →
    /// 和正在用的设置对得上 → 写进缓存。任何一步不行都不写缓存，继续用手头那份
    public func check(inUse settings: Settings?) async -> CatalogCheckResult {
        let http = self.http
        let remote = self.remote
        let signatureURL = Self.signatureURL(remote)
        let data: Data
        let signature: Data
        do {
            data = try await withRetry(retry) { try await http.get(remote) }
            signature = try await withRetry(retry) { try await http.get(signatureURL) }
        } catch {
            return .rejected("没拉到方案清单：\(error)")
        }
        guard CatalogSignature.verify(data, signature: signature, keys: keys) else {
            return .rejected("方案清单的签名不对，没有采用")
        }
        let fetched: Catalog
        do {
            fetched = try Catalog.decode(data)
        } catch {
            return .rejected("方案清单读不了：\(error)")
        }
        let current: CatalogStatus
        do {
            current = try effective()
        } catch {
            return .rejected("内置的方案清单读不了：\(error)")
        }
        guard fetched.serial > current.catalog.serial else { return .upToDate }
        let next = fetched.available(for: appVersion)
        if let settings {
            do {
                try settings.validate(next)
            } catch {
                return .rejected("这份方案清单和你现在的设置对不上（\(error)），请更新应用")
            }
        }
        do {
            try writeCache(data, signature)
        } catch {
            return .rejected("方案清单没能保存：\(error)")
        }
        var inUse = Set<String>()
        if let settings, let used = try? settings.requiredPackages(current.catalog) { inUse = Set(used.map(\.id)) }
        let status = CatalogStatus(catalog: next, origin: .online(Date()), cacheProblem: nil)
        return .updated(CatalogDiff(old: current.catalog, new: next, inUse: inUse), status)
    }

    /// 先在暂存区写好两个文件，再整个换掉缓存目录：不会只写了一半。万一中途出错，缓存没了就退回内置的
    func writeCache(_ data: Data, _ signature: Data) throws {
        let fm = FileManager.default
        let temp = paths.staging.appending(path: "catalog-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        try data.write(to: temp.appending(path: "catalog.json"))
        try signature.write(to: temp.appending(path: "catalog.json.sig"))
        if fm.fileExists(atPath: paths.catalogCache.path) {
            _ = try fm.replaceItemAt(paths.catalogCache, withItemAt: temp)
        } else {
            try fm.createDirectory(at: paths.root, withIntermediateDirectories: true)
            try fm.moveItem(at: temp, to: paths.catalogCache)
        }
    }
}
