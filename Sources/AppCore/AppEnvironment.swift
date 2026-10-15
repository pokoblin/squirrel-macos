import Foundation
import RimeKit

/// 应用用到的所有外部依赖。正式运行用 live()；测试换成假的
public struct AppEnvironment: Sendable {
    public var paths: AppPaths
    public var locations: RimeLocations
    public var catalog: Catalog
    public var compiler: any RimeCompiler
    public var squirrel: any SquirrelControlling
    public var inputSource: any InputSourceControlling
    public var userDBTool: any UserDBTool
    /// 读 macOS 文本替换
    public var textReplacements: @Sendable () throws -> TextReplacementSnapshot
    /// 取一个上游包（下载或用缓存）
    public var fetchPackage: @Sendable (PackageSpec) async throws -> CachedPackage
    /// 下载、检查、安装鼠须管（会弹系统授权框）
    public var installSquirrel: @Sendable () async throws -> InstallOutcome
    public var deployTimeout: Duration
    /// 等用户在系统设置里添加输入法，最多等多少秒
    public var activationTimeout: Double
    public var sleep: @Sendable (Duration) async -> Void

    public func deployer() -> Deployer {
        Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                 watcher: DeployWatcher(locations: locations, timeout: deployTimeout, sleep: sleep))
    }

    public static func live() throws -> AppEnvironment {
        let paths = AppPaths.default
        let locations = RimeLocations.default
        let http = URLSessionHTTPClient()
        let store = PackageStore(paths: paths, http: http, retry: .standard)
        return AppEnvironment(
            paths: paths, locations: locations, catalog: try Catalog.builtIn(),
            compiler: DeployerCompiler(locations: locations),
            squirrel: SquirrelControl(locations: locations),
            inputSource: AppInputSource(),
            userDBTool: RimeDictManager(locations: locations),
            textReplacements: { try TextReplacementReader().snapshot() },
            fetchPackage: { spec in
                do {
                    return try await store.fetch(spec)
                } catch where PackageStore.isDownloadFailure(error) {
                    // 下载不了时先用本地缓存的旧版本（设计第 7 节）
                    if let old = store.latestCached(for: spec) { return old }
                    throw error
                }
            },
            installSquirrel: {
                try await SquirrelInstaller(paths: paths, locations: locations, http: http,
                                            privileged: OsascriptPrivilegedInstaller()).install()
            },
            deployTimeout: .seconds(120), activationTimeout: 600,
            sleep: { try? await Task.sleep(for: $0) })
    }
}
