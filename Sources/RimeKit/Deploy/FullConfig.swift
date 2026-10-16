import Foundation

/// 拼出「完整的配置目录」：Rime 目录里现有的、应用不管也不会覆盖的配置文件 + 新生成的文件。
/// 应用改动（Deployer）和试打预览（PreviewWorkspace）都用它。
enum FullConfig {
    /// 返回 Rime 目录里现有的配置文件（相对路径），调用方不用再扫一遍
    @discardableResult
    static func assemble(rime: URL, ledger: Ledger, generated: URL, newPaths: [String], into full: URL) throws -> [String] {
        let existing = try RimeFiles.configFiles(in: rime)
        let newSet = Set(newPaths)
        for path in existing where ledger.entries[path] == nil && !newSet.contains(path) {
            try Deployer.copy(rime.appending(path: path), to: full.appending(path: path))
        }
        for path in newPaths {
            try Deployer.copy(generated.appending(path: path), to: full.appending(path: path))
        }
        return existing
    }
}
