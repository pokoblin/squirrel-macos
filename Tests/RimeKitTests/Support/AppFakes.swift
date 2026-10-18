import Foundation
@testable import AppCore
@testable import RimeKit

extension TransferFixtures.Machine {
    /// 这台假 Mac 的应用依赖：包从自造的缓存里取，不联网
    func environment(
        input: FakeInputSource = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true)),
        compiler: FakeCompiler = FakeCompiler(),
        textReplacements: @escaping @Sendable () throws -> TextReplacementSnapshot = {
            TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0)
        },
        install: @escaping @Sendable () async throws -> InstallOutcome = { .alreadyInstalled("1.1.2") },
        catalogHTTP: FakeHTTPClient = FakeHTTPClient(),
        catalogKeys: [Data] = []
    ) -> AppEnvironment {
        let packages = self.packages
        let catalog = self.catalog
        let catalogStore = CatalogStore(paths: paths, http: catalogHTTP, retry: .immediate, builtIn: { catalog },
                                        keys: catalogKeys, remote: TestCatalogs.remote, appVersion: AppVersion("0.2.0")!)
        return AppEnvironment(
            paths: paths, locations: locations, catalogStore: catalogStore,
            catalogs: CatalogHolder(try! catalogStore.effective()), compiler: compiler, squirrel: squirrel,
            inputSource: input, userDBTool: tool, textReplacements: textReplacements,
            fetchPackage: { spec in
                guard let package = packages[spec.id] else { throw TakeoverError.missingPackage(spec.id) }
                return package
            },
            cachedPackage: { packages[$0.id] },
            installSquirrel: install, deployTimeout: .milliseconds(20), activationTimeout: 5, sleep: { _ in },
            // 默认：上游和本地一样（都是最新的）
            latestPackageVersion: { spec in
                guard let package = packages[spec.id] else { throw TakeoverError.missingPackage(spec.id) }
                return ResolvedSource(version: package.info.version, downloadURL: package.info.sourceURL)
            })
    }
}
