import Foundation
import RimeKit

/// 应用用到的所有外部依赖。正式运行用 live()；测试换成假的
public struct AppEnvironment: Sendable {
    public var paths: AppPaths
    public var locations: RimeLocations
    /// 方案清单：读内置和缓存的、检查在线更新
    public var catalogStore: CatalogStore
    /// 生效的方案清单（引导和主窗口共用）
    public var catalogs: CatalogHolder
    public var catalog: Catalog { catalogs.status.catalog }
    public var compiler: any RimeCompiler
    public var squirrel: any SquirrelControlling
    public var inputSource: any InputSourceControlling
    public var userDBTool: any UserDBTool
    /// 读 macOS 文本替换
    public var textReplacements: @Sendable () throws -> TextReplacementSnapshot
    /// 下载一个上游包（已经是最新的就直接用缓存；下载失败就抛错）
    public var fetchPackage: @Sendable (PackageSpec) async throws -> CachedPackage
    /// 本地缓存里最新的这个包（下载失败时可以先用它）
    public var cachedPackage: @Sendable (PackageSpec) -> CachedPackage?
    /// 下载、检查、安装鼠须管（会弹系统授权框）
    public var installSquirrel: @Sendable () async throws -> InstallOutcome
    public var deployTimeout: Duration
    /// 等用户在系统设置里添加输入法，最多等多少秒
    public var activationTimeout: Double
    public var sleep: @Sendable (Duration) async -> Void
    /// 新建一个试打引擎（辅助程序）。超时、崩溃以后的会话不能再用，重试时再建一个
    public var previewEngine: @Sendable () throws -> any PreviewEngine = { throw PreviewError.helperMissing }

    public func deployer() -> Deployer {
        Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                 watcher: DeployWatcher(locations: locations, timeout: deployTimeout, sleep: sleep))
    }

    public static func live() throws -> AppEnvironment {
        let paths = AppPaths.default
        let locations = RimeLocations.default
        let http = URLSessionHTTPClient()
        let store = PackageStore(paths: paths, http: http, retry: .standard)
        let catalogStore = CatalogStore(paths: paths, http: http)
        var env = AppEnvironment(
            paths: paths, locations: locations, catalogStore: catalogStore, catalogs: CatalogHolder(try catalogStore.effective()),
            compiler: DeployerCompiler(locations: locations),
            squirrel: SquirrelControl(locations: locations),
            inputSource: AppInputSource(),
            userDBTool: RimeDictManager(locations: locations),
            textReplacements: { try TextReplacementReader().snapshot() },
            fetchPackage: { try await store.fetch($0) },
            cachedPackage: { store.latestCached(for: $0) },
            installSquirrel: {
                try await SquirrelInstaller(paths: paths, locations: locations, http: http,
                                            privileged: OsascriptPrivilegedInstaller()).install()
            },
            deployTimeout: .seconds(120), activationTimeout: 600,
            sleep: { try? await Task.sleep(for: $0) })
        env.previewEngine = {
            guard let helper = PreviewHelperLocator.locate() else { throw PreviewError.helperMissing }
            return PreviewSession(helper: helper, squirrelApp: locations.squirrelApp)
        }
        return env
    }
}
