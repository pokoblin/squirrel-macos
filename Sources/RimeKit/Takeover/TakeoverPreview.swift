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
        let warnings = result.warnings + (try Self.editedUpstream(replaced, existing: existing, rime: dir, generated: out))
        return TakeoverPreview(replaced: replaced, unchanged: unchanged, added: added,
                               kept: existing.subtracting(generated).sorted(), warnings: warnings)
    }

    /// 要换掉的上游文件里，用户可能直接改过的：词库多导入了用户自己的词库（换掉后就不再导入）；方案文件
    static func editedUpstream(_ replaced: [String], existing: Set<String>, rime: URL, generated: URL) throws -> [String] {
        var warnings: [String] = []
        for path in replaced where path.hasSuffix(".dict.yaml") {
            let mine = TakeoverFiles.importTables(try String(contentsOf: rime.appending(path: path), encoding: .utf8)) ?? []
            let theirs = Set(TakeoverFiles.importTables(try String(contentsOf: generated.appending(path: path), encoding: .utf8)) ?? [])
            let extra = mine.filter { !theirs.contains($0) && existing.contains("\($0).dict.yaml") }
            if !extra.isEmpty {
                warnings.append("\(path) 现在还导入了 \(extra.joined(separator: "、"))；接管后换成上游版本，就不再导入了（这些词库文件原样保留，原来的 \(path) 在备份里）")
            }
        }
        let schemas = replaced.filter { $0.hasSuffix(".schema.yaml") }
        if !schemas.isEmpty {
            warnings.append("这些方案文件和上游最新版不一样（可能是你直接改过，也可能是旧版本），接管后换成最新版，原文件在备份里：\(schemas.joined(separator: "、"))")
        }
        return warnings
    }
}
