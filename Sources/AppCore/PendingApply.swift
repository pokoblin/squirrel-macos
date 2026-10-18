import Foundation
import RimeKit

/// 「有更新还没应用」：方案清单更新改到了在用的包、在用的方案包上游有新版本。
/// 存在数据目录里，退出再打开还提醒；都没有时删掉文件
struct PendingApply: Codable, Equatable, Sendable {
    var catalog = false
    /// 上游有新版本的包 id
    var packages: [String] = []

    static func file(_ paths: AppPaths) -> URL {
        paths.root.appending(path: "pending-apply.json")
    }

    /// 读不了（没有、坏了）就当没有：最坏是少提醒一次，下次检查更新还会查出来
    static func load(_ paths: AppPaths) -> PendingApply {
        guard let data = try? Data(contentsOf: file(paths)),
              let pending = try? JSONCoding.decoder.decode(PendingApply.self, from: data) else { return PendingApply() }
        return pending
    }

    /// 写不了不报错：只是提醒，不影响配置
    func save(_ paths: AppPaths) {
        let url = Self.file(paths)
        if self == PendingApply() {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try? JSONCoding.encoder.encode(self).write(to: url, options: .atomic)
    }
}
