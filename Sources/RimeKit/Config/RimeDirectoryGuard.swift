import Darwin
import Foundation

/// 判断一个路径是不是（或在）真实的 ~/Library/Rime。
/// 生成配置、模拟打字都只能用副本；这里宁可多拒绝，也不能放过。
public enum RimeDirectoryGuard {
    private struct FileID: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// 可能的家目录：当前进程的、$HOME、passwd 里的、sudo 之前的用户的
    public static func defaultHomes() -> [String] {
        var homes = [NSHomeDirectory()]
        if let home = ProcessInfo.processInfo.environment["HOME"] { homes.append(home) }
        if let pw = getpwuid(getuid()) { homes.append(String(cString: pw.pointee.pw_dir)) }
        if let sudo = ProcessInfo.processInfo.environment["SUDO_UID"], let uid = uid_t(sudo), let pw = getpwuid(uid) {
            homes.append(String(cString: pw.pointee.pw_dir))
        }
        return homes
    }

    public static func isInsideRealRimeDirectory(_ url: URL, homes: [String] = defaultHomes()) -> Bool {
        // 带 .. 的路径，按字面和按真实路径解析的结果可能不一样，直接拒绝
        if url.pathComponents.contains("..") { return true }
        let libraries = Set(homes.compactMap { fileID(($0 as NSString).appendingPathComponent("Library")) })
        if libraries.isEmpty { return true }
        // 各个家目录里 Library/Rime 实际指向的目录（stat 会跟随符号链接，同步盘里的配置也认得出）
        let rimes = Set(homes.compactMap { fileID(($0 as NSString).appendingPathComponent("Library/Rime")) })

        // 找到最近一个存在的上级目录，解析掉符号链接；不存在的部分原样接在后面
        let fm = FileManager.default
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !fm.fileExists(atPath: existing.path) {
            rest.insert(existing.lastPathComponent, at: 0)
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { return true }
            existing = parent
        }
        guard let resolved = realpath(existing.path, nil) else { return true }
        let base = String(cString: resolved)
        free(resolved)

        var current = "/"
        for component in URL(fileURLWithPath: base).pathComponents.dropFirst() + rest {
            let parent = current
            current = (current as NSString).appendingPathComponent(component)
            if let id = fileID(current), rimes.contains(id) { return true }
            if component.caseInsensitiveCompare("Rime") == .orderedSame,
               let id = fileID(parent), libraries.contains(id) {
                return true
            }
        }
        return false
    }

    private static func fileID(_ path: String) -> FileID? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileID(device: info.st_dev, inode: info.st_ino)
    }
}
