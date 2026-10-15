import Foundation

/// 方案清单：有哪些包、从哪下载、装哪些文件、依赖谁（设计第 4 节）
public struct Catalog: Sendable, Equatable, Codable {
    public static let supportedFormatVersion = 1

    public let formatVersion: Int
    /// 发布序号：在线清单只接受比手头那份更大的（防回滚，在线方案清单设计 3.1）。没写的当成 0
    public let serial: Int
    public let packages: [PackageSpec]

    public init(formatVersion: Int = Catalog.supportedFormatVersion, serial: Int, packages: [PackageSpec]) {
        self.formatVersion = formatVersion
        self.serial = serial
        self.packages = packages
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, serial, packages }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        serial = try c.decodeIfPresent(Int.self, forKey: .serial) ?? 0
        packages = try c.decode([PackageSpec].self, forKey: .packages)
    }

    public func package(_ id: String) -> PackageSpec? {
        packages.first { $0.id == id }
    }

    /// 这个方案属于哪个包
    public func packageOwning(schema: String) -> PackageSpec? {
        packages.first { $0.schemas.contains { $0.id == schema } }
    }

    /// 读取并校验。先只读格式版本号，版本不对就不往下解析。
    public static func decode(_ data: Data) throws -> Catalog {
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONCoding.decoder.decode(Header.self, from: data)
        guard header.formatVersion == supportedFormatVersion else {
            throw CatalogError.unsupportedFormat(header.formatVersion)
        }
        let catalog = try JSONCoding.decoder.decode(Catalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    /// 打包在应用里的清单
    public static func builtIn() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.builtInMissing
        }
        return try decode(Data(contentsOf: url))
    }

    public func validate() throws {
        var packageIDs = Set<String>()
        for p in packages where !packageIDs.insert(p.id).inserted {
            throw CatalogError.duplicatePackageID(p.id)
        }
        var schemaIDs = Set<String>()
        for s in packages.flatMap(\.schemas) where !schemaIDs.insert(s.id).inserted {
            throw CatalogError.duplicateSchemaID(s.id)
        }
        for p in packages {
            for d in p.dependencies where !packageIDs.contains(d) {
                throw CatalogError.unknownDependency(package: p.id, dependency: d)
            }
        }
        for p in packages {
            if let v = p.minAppVersion, AppVersion(v) == nil {
                throw CatalogError.badMinAppVersion(package: p.id, value: v)
            }
        }
        try checkCycles()
        for p in packages {
            for file in p.requiredFiles {
                let included = p.include.contains { $0.matches(file) } && !p.exclude.contains { $0.matches(file) }
                if !included { throw CatalogError.requiredFileNotIncluded(package: p.id, file: file) }
            }
        }
        for p in packages {
            for file in p.userDicts {
                let included = p.include.contains { $0.matches(file) } && !p.exclude.contains { $0.matches(file) }
                guard included, !file.contains("/"), file.hasSuffix(".dict.yaml") else {
                    throw CatalogError.badUserDict(package: p.id, file: file)
                }
            }
        }
        for p in packages {
            for option in p.options {
                guard option.choice(option.defaultChoice) != nil else {
                    throw CatalogError.unknownDefaultChoice(package: p.id, option: option.id)
                }
                for choice in option.choices {
                    for d in choice.dependencies where !packageIDs.contains(d) {
                        throw CatalogError.unknownDependency(package: p.id, dependency: d)
                    }
                    for schema in choice.patches.keys.sorted() where !p.schemas.contains(where: { $0.id == schema }) {
                        throw CatalogError.patchForUnknownSchema(package: p.id, schema: schema)
                    }
                }
            }
        }
    }

    /// 去掉这个版本的应用用不了的包（minAppVersion 更高），以及因此缺了依赖（包括选项里的依赖）的包（设计 3.4、4.1）
    public func available(for appVersion: AppVersion) -> Catalog {
        var kept = packages.filter { p in
            guard let text = p.minAppVersion, let needed = AppVersion(text) else { return true }
            return needed <= appVersion
        }
        while true {
            let ids = Set(kept.map(\.id))
            let next = kept.filter { p in
                p.dependencies.allSatisfy(ids.contains)
                    && p.options.allSatisfy { $0.choices.allSatisfy { $0.dependencies.allSatisfy(ids.contains) } }
            }
            if next.count == kept.count { break }
            kept = next
        }
        return Catalog(formatVersion: formatVersion, serial: serial, packages: kept)
    }

    /// 要装这些包时的顺序：依赖在前，每个包只出现一次
    public func installOrder(for ids: [String]) throws -> [PackageSpec] {
        var result: [PackageSpec] = []
        var seen = Set<String>()
        func visit(_ id: String) throws {
            if seen.contains(id) { return }
            guard let p = package(id) else { throw CatalogError.unknownPackage(id) }
            seen.insert(id)
            for d in p.dependencies { try visit(d) }
            result.append(p)
        }
        for id in ids { try visit(id) }
        return result
    }

    private func checkCycles() throws {
        enum State { case visiting, done }
        var state: [String: State] = [:]
        var stack: [String] = []
        func visit(_ id: String) throws {
            if state[id] == .done { return }
            if state[id] == .visiting {
                let start = stack.firstIndex(of: id) ?? 0
                throw CatalogError.dependencyCycle(Array(stack[start...]) + [id])
            }
            state[id] = .visiting
            stack.append(id)
            for d in package(id)?.dependencies ?? [] { try visit(d) }
            stack.removeLast()
            state[id] = .done
        }
        for p in packages { try visit(p.id) }
    }
}

public struct PackageSpec: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let summary: String
    public let license: String
    public let homepage: URL
    public let source: PackageSource
    /// 用来找包根目录的文件（相对包根目录）。zip 里顶层目录名不固定，靠它定位。
    public let anchor: String
    public let include: [FileGlob]
    public let exclude: [FileGlob]
    /// 解压后必须存在的文件；缺了说明上游结构变了
    public let requiredFiles: [String]
    public let schemas: [SchemaSpec]
    public let dependencies: [String]
    /// 包的可选项；JSON 里可以不写
    public let options: [PackageOption]
    /// 上游自带的个人词库模板（包根目录下的 .dict.yaml）：用户会往里加词。
    /// 接管已有配置时，和上游不一样的就当个人词库收进 personal/；JSON 里可以不写
    public let userDicts: [String]
    /// 下架了：已经在用的照常能用，「可以启用的方案」里不再列出（设计 3.2）；JSON 里可以不写
    public let deprecated: Bool
    /// 要求的最低应用版本（例如 "0.3.0"）；比当前版本高的包当它不存在（设计 3.4）。JSON 里可以不写
    public let minAppVersion: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, license, homepage, source, anchor, include, exclude, requiredFiles, schemas, dependencies, options, userDicts,
             deprecated, minAppVersion
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decode(String.self, forKey: .summary)
        license = try c.decode(String.self, forKey: .license)
        homepage = try c.decode(URL.self, forKey: .homepage)
        source = try c.decode(PackageSource.self, forKey: .source)
        anchor = try c.decode(String.self, forKey: .anchor)
        include = try c.decode([FileGlob].self, forKey: .include)
        exclude = try c.decode([FileGlob].self, forKey: .exclude)
        requiredFiles = try c.decode([String].self, forKey: .requiredFiles)
        schemas = try c.decode([SchemaSpec].self, forKey: .schemas)
        dependencies = try c.decode([String].self, forKey: .dependencies)
        options = try c.decodeIfPresent([PackageOption].self, forKey: .options) ?? []
        userDicts = try c.decodeIfPresent([String].self, forKey: .userDicts) ?? []
        deprecated = try c.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
        minAppVersion = try c.decodeIfPresent(String.self, forKey: .minAppVersion)
    }
}

public struct SchemaSpec: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let category: SchemaCategory

    public init(id: String, name: String, category: SchemaCategory) {
        self.id = id
        self.name = name
        self.category = category
    }
}

public enum SchemaCategory: String, Sendable, Equatable, Codable {
    case pinyin, shuangpin, wubi, other
}

public enum PackageSource: Sendable, Equatable, Codable {
    /// GitHub Release 的附件，版本用附件的 updated_at
    case githubReleaseAsset(repo: String, tag: String, asset: String)
    /// GitHub 某个分支的最新提交，版本用提交号，并按提交号下载
    case githubBranch(repo: String, branch: String)

    private enum CodingKeys: String, CodingKey { case type, repo, tag, asset, branch }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "githubReleaseAsset":
            self = .githubReleaseAsset(
                repo: try c.decode(String.self, forKey: .repo),
                tag: try c.decode(String.self, forKey: .tag),
                asset: try c.decode(String.self, forKey: .asset))
        case "githubBranch":
            self = .githubBranch(
                repo: try c.decode(String.self, forKey: .repo),
                branch: try c.decode(String.self, forKey: .branch))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "不认识的下载来源类型：\(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .githubReleaseAsset(repo, tag, asset):
            try c.encode("githubReleaseAsset", forKey: .type)
            try c.encode(repo, forKey: .repo)
            try c.encode(tag, forKey: .tag)
            try c.encode(asset, forKey: .asset)
        case let .githubBranch(repo, branch):
            try c.encode("githubBranch", forKey: .type)
            try c.encode(repo, forKey: .repo)
            try c.encode(branch, forKey: .branch)
        }
    }
}
