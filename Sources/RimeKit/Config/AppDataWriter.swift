import Foundation

/// 换掉应用里保存的设置和个人内容（接管、导入时用）
public enum AppDataWriter {
    /// 换掉整个 personal/（个人词库 + 手动短语），最后保存设置。
    /// 新内容先写在旁边，写好了再整体换上；中途出错就换回原来的，原来的个人内容和设置都不丢
    public static func replace(settings: Settings, dicts: [URL], phrases: [Phrase], paths: AppPaths) throws {
        let fm = FileManager.default
        let id = UUID().uuidString
        let fresh = paths.root.appending(path: "personal.new-\(id)", directoryHint: .isDirectory)
        let old = paths.root.appending(path: "personal.old-\(id)", directoryHint: .isDirectory)
        defer {
            try? fm.removeItem(at: fresh)
            try? fm.removeItem(at: old)
        }

        // 1. 新内容写在旁边
        let freshDicts = fresh.appending(path: paths.personalDicts.lastPathComponent, directoryHint: .isDirectory)
        try fm.createDirectory(at: freshDicts, withIntermediateDirectories: true)
        for url in dicts {
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: freshDicts.appending(path: url.lastPathComponent))
        }
        if !phrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(phrases)).utf8)
                .write(to: fresh.appending(path: paths.personalPhrases.lastPathComponent))
        }

        // 2. 换上，再保存设置；出错就换回去
        let hadOld = fm.fileExists(atPath: paths.personal.path)
        if hadOld { try fm.moveItem(at: paths.personal, to: old) }
        do {
            try fm.moveItem(at: fresh, to: paths.personal)
            try SettingsStore(paths: paths).save(settings)
        } catch {
            if fm.fileExists(atPath: paths.personal.path) { try? fm.removeItem(at: paths.personal) }
            if hadOld { try? fm.moveItem(at: old, to: paths.personal) }
            throw error
        }
    }
}
