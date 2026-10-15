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
}
