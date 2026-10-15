import Foundation

/// 接管后哪些文件会变：在暂存区按识别结果生成一遍，和现在的 Rime 目录逐个文件比。只读，不改 Rime 目录。
public struct TakeoverPreview: Sendable, Equatable {
    /// 现在有、接管后内容会变（上游的新版本、应用重新生成的补丁等）
    public let replaced: [String]
    /// 现在有、内容一样，只是以后归应用管
    public let unchanged: [String]
    /// 现在没有、接管后新加的
    public let added: [String]
    /// 应用不管、原样保留的
    public let kept: [String]
    /// 生成时的提醒
    public let warnings: [String]

    public static func make(_ proposal: TakeoverProposal, rime: URL, catalog: Catalog, packages: [String: CachedPackage],
                            textReplacement: [Phrase], staging: URL) throws -> TakeoverPreview {
        let fm = FileManager.default
        let out = staging.appending(path: "takeover-preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: out) }
        let input = proposal.generationInput(catalog: catalog, packages: packages, textReplacement: textReplacement)
        let result = try ConfigGenerator().generate(input, into: out)
        let dir = rime.resolvingSymlinksInPath()
        let existing = Set(try RimeFiles.configFiles(in: rime))
        var replaced: [String] = []
        var unchanged: [String] = []
        var added: [String] = []
        for file in result.files {
            guard existing.contains(file.path) else {
                added.append(file.path)
                continue
            }
            if fm.contentsEqual(atPath: dir.appending(path: file.path).path, andPath: out.appending(path: file.path).path) {
                unchanged.append(file.path)
            } else {
                replaced.append(file.path)
            }
        }
        let generated = Set(result.files.map(\.path))
        return TakeoverPreview(replaced: replaced, unchanged: unchanged, added: added,
                               kept: existing.subtracting(generated).sorted(), warnings: result.warnings)
    }
}
