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
        install: @escaping @Sendable () async throws -> InstallOutcome = { .alreadyInstalled("1.1.2") }
    ) -> AppEnvironment {
        let packages = self.packages
        return AppEnvironment(
            paths: paths, locations: locations, catalog: catalog, compiler: compiler, squirrel: squirrel,
            inputSource: input, userDBTool: tool, textReplacements: textReplacements,
            fetchPackage: { spec in
                guard let package = packages[spec.id] else { throw TakeoverError.missingPackage(spec.id) }
                return package
            },
            installSquirrel: install, deployTimeout: .milliseconds(20), activationTimeout: 5, sleep: { _ in })
    }
}
