import Foundation

/// 换掉应用里保存的设置和个人内容（接管、导入时用）
public enum AppDataWriter {
    /// 换掉整个 personal/（个人词库 + 手动短语），最后保存设置：个人内容没存好就不会有设置
    public static func replace(settings: Settings, dicts: [URL], phrases: [Phrase], paths: AppPaths) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.personal.path) { try fm.removeItem(at: paths.personal) }
        try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        for url in dicts {
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: paths.personalDicts.appending(path: url.lastPathComponent))
        }
        if !phrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(phrases)).utf8).write(to: paths.personalPhrases, options: .atomic)
        }
        try SettingsStore(paths: paths).save(settings)
    }
}
