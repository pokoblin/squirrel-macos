import Foundation

/// Rime 用户目录里的文件分类
public enum RimeFiles {
    /// Rime 自己的运行文件：不备份、不由应用写、也不算外部文件
    public static func isRimeOwned(_ path: String) -> Bool {
        let first = path.split(separator: "/").first.map(String.init) ?? path
        let name = (path as NSString).lastPathComponent
        if first == "build" || first == "sync" { return true }
        if path == "installation.yaml" || path == "user.yaml" { return true }
        if first.hasSuffix(".userdb") || name.hasSuffix(".userdb.txt") { return true }
        if name == ".DS_Store" { return true }
        if name.hasPrefix(".") && name.hasSuffix(".squirrel-macos-tmp") { return true }
        return false
    }

    /// 目录里的配置文件（相对路径，排好序）：普通文件和符号链接，跳过 Rime 自己的运行文件。目录不存在时返回空。
    public static func configFiles(in dir: URL) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        return try fm.subpathsOfDirectory(atPath: dir.path).filter { sub in
            guard !isRimeOwned(sub) else { return false }
            let type = (try? fm.attributesOfItem(atPath: dir.appending(path: sub).path))?[.type] as? FileAttributeType
            return type == .typeRegular || type == .typeSymbolicLink
        }.sorted()
    }
}
