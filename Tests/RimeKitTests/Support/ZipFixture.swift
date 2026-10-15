import Foundation
@testable import RimeKit

/// 用 ditto 现场造一个 zip，内容由测试决定
enum ZipFixture {
    /// files：相对路径 → 文字内容；topFolder 不为 nil 时 zip 里多一层这个名字的目录；
    /// symlinks：相对路径 → 链接指向的路径
    static func make(_ files: [String: String], topFolder: String?, symlinks: [String: String] = [:]) throws -> Data {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "zipfixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: base) }
        let content = base.appending(path: topFolder ?? "content", directoryHint: .isDirectory)
        try fm.createDirectory(at: content, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = content.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        for (path, target) in symlinks {
            try fm.createSymbolicLink(atPath: content.appending(path: path).path, withDestinationPath: target)
        }
        let zip = base.appending(path: "out.zip")
        var args = ["-c", "-k", "--sequesterRsrc"]
        if topFolder != nil { args.append("--keepParent") }
        args += [content.path, zip.path]
        let result = try Shell.run("/usr/bin/ditto", args)
        precondition(result.status == 0, "造 zip 失败：\(result.stderr)")
        return try Data(contentsOf: zip)
    }
}
