import Foundation

/// 应用自己的数据目录。默认是 ~/Library/Application Support/squirrel-macos，
/// 测试和 rimectl --data-dir 可以换成别的目录。
public struct AppPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appending(path: "squirrel-macos", directoryHint: .isDirectory))
    }

    /// 上游包缓存，按「包名@版本」存放
    public var packages: URL { root.appending(path: "packages", directoryHint: .isDirectory) }

    /// 生成、下载用的暂存区
    public var staging: URL { root.appending(path: "staging", directoryHint: .isDirectory) }

    /// 用户的所有选择
    public var settingsFile: URL { root.appending(path: "settings.json") }

    /// 个人内容的正本：个人词库、手动短语
    public var personal: URL { root.appending(path: "personal", directoryHint: .isDirectory) }
    public var personalDicts: URL { personal.appending(path: "dicts", directoryHint: .isDirectory) }
    public var personalPhrases: URL { personal.appending(path: "phrases.txt") }

    /// 应用写进 ~/Library/Rime 的文件和哈希
    public var ledgerFile: URL { root.appending(path: "ledger.json") }

    /// 每次写入前对 ~/Library/Rime 的备份
    public var backups: URL { root.appending(path: "backups", directoryHint: .isDirectory) }

    /// 导入前把应用里原来的设置和个人内容另存在这里（Rime 目录的备份不含这些）
    public var beforeImport: URL { root.appending(path: "before-import", directoryHint: .isDirectory) }

    /// 防止应用和 rimectl 同时改
    public var lockFile: URL { root.appending(path: "lock") }
}
