import Foundation

/// 用户确认接管后：按识别结果走 6.1 写入；写入成功后才保存设置和个人内容
public struct TakeoverApplier: Sendable {
    let deployer: Deployer

    public init(deployer: Deployer) {
        self.deployer = deployer
    }

    public func confirm(_ proposal: TakeoverProposal, catalog: Catalog, packages: [String: CachedPackage],
                        textReplacement: [Phrase], force: Bool) async throws -> ApplyOutcome {
        let paths = deployer.paths
        let fm = FileManager.default
        guard try Ledger.load(paths).entries.isEmpty else { throw TakeoverError.alreadyManaged }
        if fm.fileExists(atPath: paths.settingsFile.path), !force {
            throw TakeoverError.settingsExist(paths.settingsFile.path)
        }

        // 个人词库先复制一份到暂存区：写入后才放进 personal/，中途停下不会动正本
        let work = paths.staging.appending(path: "takeover-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        let dicts = work.appending(path: "dicts", directoryHint: .isDirectory)
        try fm.createDirectory(at: dicts, withIntermediateDirectories: true)
        var staged = proposal
        staged.personalDicts = try proposal.personalDicts.map { url in
            let target = dicts.appending(path: url.lastPathComponent)
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: target)
            return target
        }

        // 用户在预览里确认的就是这些覆盖；第一次的备份永久保留（Deployer.apply 负责）
        let outcome = try await deployer.apply(
            staged.generationInput(catalog: catalog, packages: packages, textReplacement: textReplacement),
            options: ApplyOptions(overwriteExternalChanges: true))
        guard case .applied = outcome else { return outcome }

        try SettingsStore(paths: paths).save(proposal.settings)
        if fm.fileExists(atPath: paths.personal.path) { try fm.removeItem(at: paths.personal) }
        try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        for url in staged.personalDicts {
            try fm.copyItem(at: url, to: paths.personalDicts.appending(path: url.lastPathComponent))
        }
        if !proposal.manualPhrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(proposal.manualPhrases)).utf8)
                .write(to: paths.personalPhrases, options: .atomic)
        }
        return outcome
    }
}
