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
        let dictFiles = try proposal.personalDicts.map { url in
            let target = dicts.appending(path: url.lastPathComponent)
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: target)
            return target
        }
        var staged = proposal
        staged.personalDicts = dictFiles

        // 用户在预览里确认的就是这些覆盖；第一次的备份永久保留（Deployer.apply 负责）。
        // 文件写好后、通知鼠须管之前就保存设置和个人内容（还在锁里）：等部署最多两分钟，这时被中断也不会留下半截状态
        let input = staged.generationInput(catalog: catalog, packages: packages, textReplacement: textReplacement)
        // 记下这次用的文本替换（只存哈希）
        let settings = proposal.settings.recordingTextReplacement(input.textReplacementPhrases)
        let phrases = proposal.manualPhrases
        return try await deployer.apply(
            input,
            options: ApplyOptions(overwriteExternalChanges: true),
            afterWrite: { try AppDataWriter.replace(settings: settings, dicts: dictFiles, phrases: phrases, paths: paths) })
    }
}
