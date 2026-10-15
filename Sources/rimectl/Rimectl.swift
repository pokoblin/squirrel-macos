import Foundation
import RimeKit

/// rimectl：RimeKit 的命令行入口，用来在测试机里通过 SSH 跑完整流程
@main
struct Rimectl {
    struct Context: Sendable {
        var http: any HTTPClient
        var retry: RetryPolicy
        var catalog: @Sendable () throws -> Catalog
        var defaultPaths: AppPaths
        var output: Output
    }

    static let usage = """
    用法：
      rimectl catalog                                          列出内置方案清单
      rimectl fetch [--data-dir 目录] [--cache-only] 包名...      下载（或从缓存取）这些包和它们的依赖
      rimectl settings init <rime-ice|flypy|wubi-pinyin> [--force]   写入起步设置
      rimectl settings show                                    打印当前设置
      rimectl generate --out 目录 [--data-dir 目录] [--cache-only]   按设置生成一份 Rime 配置（只往空目录写）
    """

    static func main() async {
        let context = Context(
            http: URLSessionHTTPClient(),
            retry: .standard,
            catalog: { try Catalog.builtIn() },
            defaultPaths: .default,
            output: Output(echo: true))
        exit(await run(Array(CommandLine.arguments.dropFirst()), context))
    }

    static func run(_ args: [String], _ context: Context) async -> Int32 {
        let out = context.output
        var dataDir: String?
        var cacheOnly = false
        var outDir: String?
        var force = false
        var positional: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--data-dir":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                dataDir = args[i + 1]
                i += 2
            case "--out":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                outDir = args[i + 1]
                i += 2
            case "--force":
                force = true
                i += 1
            case "--cache-only":
                cacheOnly = true
                i += 1
            case "-h", "--help":
                out.line(usage)
                return 0
            default:
                positional.append(args[i])
                i += 1
            }
        }
        guard let command = positional.first else { out.error(usage); return 2 }
        let paths = dataDir.map { AppPaths(root: URL(fileURLWithPath: $0, isDirectory: true)) } ?? context.defaultPaths

        do {
            switch command {
            case "catalog":
                try listCatalog(try context.catalog(), out)
                return 0
            case "settings":
                return try settingsCommand(Array(positional.dropFirst()), force: force, paths: paths, context)
            case "generate":
                guard let outDir else { out.error(usage); return 2 }
                return try await generate(out: URL(fileURLWithPath: outDir, isDirectory: true),
                                          cacheOnly: cacheOnly, paths: paths, context)
            case "fetch":
                let ids = Array(positional.dropFirst())
                guard !ids.isEmpty else { out.error(usage); return 2 }
                return try await fetch(ids, cacheOnly: cacheOnly, paths: paths, context)
            default:
                out.error(usage)
                return 2
            }
        } catch {
            out.error(String(describing: error))
            return 1
        }
    }

    private static func listCatalog(_ catalog: Catalog, _ out: Output) throws {
        for p in catalog.packages {
            out.line("\(p.id)  \(p.name)  \(p.license)")
            for s in p.schemas {
                out.line("  - \(s.id)  \(s.name)")
            }
        }
    }

    /// 取一个包：cacheOnly 时只用本地缓存；下载失败时提示可以用旧版本。失败返回 nil（已经输出了错误）。
    private static func obtain(_ spec: PackageSpec, cacheOnly: Bool, store: PackageStore, _ out: Output) async throws -> CachedPackage? {
        if cacheOnly {
            guard let pkg = store.latestCached(for: spec) else {
                out.error("\(spec.id)：本地没有缓存")
                return nil
            }
            return pkg
        }
        do {
            return try await store.fetch(spec)
        } catch where PackageStore.isDownloadFailure(error) {
            var message = "\(spec.id)：下载失败。\(error)"
            if let old = store.latestCached(for: spec) {
                message += "\n本地有缓存的旧版本 \(old.info.version)，可以加 --cache-only 先用它"
            }
            out.error(message)
            return nil
        }
    }

    private static func fetch(_ ids: [String], cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        let catalog = try context.catalog()
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        for spec in try catalog.installOrder(for: ids) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            report(pkg, out)
        }
        return 0
    }

    private static func settingsCommand(_ args: [String], force: Bool, paths: AppPaths, _ context: Context) throws -> Int32 {
        let out = context.output
        let store = SettingsStore(paths: paths)
        switch args.first {
        case "init":
            guard args.count == 2, let starter = Starter(rawValue: args[1]) else { out.error(usage); return 2 }
            if try store.load() != nil, !force {
                out.error("已经有设置了：\(paths.settingsFile.path)。要覆盖就加 --force")
                return 1
            }
            let settings = Settings.starter(starter)
            try settings.validate(try context.catalog())
            try store.save(settings)
            out.line("已写入起步设置「\(starter.displayName)」：\(paths.settingsFile.path)")
            return 0
        case "show":
            guard let settings = try store.load() else {
                out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
                return 1
            }
            out.line(String(decoding: try JSONCoding.encoder.encode(settings), as: UTF8.self))
            return 0
        default:
            out.error(usage)
            return 2
        }
    }

    private static func generate(out target: URL, cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        if RimeDirectoryGuard.isInsideRealRimeDirectory(target) {
            out.error("拒绝：--out 指向真实的 ~/Library/Rime（\(target.path)）。generate 只往别的空目录里写")
            return 1
        }
        guard let settings = try SettingsStore(paths: paths).load() else {
            out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
            return 1
        }
        let catalog = try context.catalog()
        try settings.validate(catalog)
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: try PersonalContent.load(from: paths), textReplacementPhrases: [])
        let result = try ConfigGenerator().generate(input, into: target)
        for warning in result.warnings { out.line("注意：\(warning)") }
        out.line("已生成 \(result.files.count) 个文件到 \(target.path)")
        return 0
    }

    private static func report(_ pkg: CachedPackage, _ out: Output) {
        out.line("\(pkg.info.id)@\(pkg.info.version)  \(pkg.info.files.count) 个文件  \(pkg.filesDirectory.path)")
    }
}
