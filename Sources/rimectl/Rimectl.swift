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
      rimectl catalog                                    列出内置方案清单
      rimectl fetch [--data-dir 目录] [--cache-only] 包名...   下载（或从缓存取）这些包和它们的依赖
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
        var positional: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--data-dir":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                dataDir = args[i + 1]
                i += 2
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

    private static func fetch(_ ids: [String], cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        let catalog = try context.catalog()
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        for spec in try catalog.installOrder(for: ids) {
            if cacheOnly {
                guard let pkg = store.latestCached(spec.id) else {
                    out.error("\(spec.id)：本地没有缓存")
                    return 1
                }
                report(pkg, out)
                continue
            }
            do {
                report(try await store.fetch(spec), out)
            } catch let error as HTTPError {
                var message = "\(spec.id)：下载失败。\(error)"
                if let old = store.latestCached(spec.id) {
                    message += "\n本地有缓存的旧版本 \(old.info.version)，可以加 --cache-only 先用它"
                }
                out.error(message)
                return 1
            }
        }
        return 0
    }

    private static func report(_ pkg: CachedPackage, _ out: Output) {
        out.line("\(pkg.info.id)@\(pkg.info.version)  \(pkg.info.files.count) 个文件  \(pkg.filesDirectory.path)")
    }
}
