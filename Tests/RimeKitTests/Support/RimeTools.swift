import Foundation
@testable import RimeKit

/// 调用宿主机上鼠须管自带的 rime_deployer 和打字检查工具。只读使用鼠须管，只处理临时目录。
enum RimeTools {
    static let squirrel = "/Library/Input Methods/Squirrel.app/Contents"

    static var installed: Bool {
        FileManager.default.isExecutableFile(atPath: squirrel + "/MacOS/rime_deployer")
    }

    /// 仓库里的 tools/vm/rime-type-probe（./tools/vm/build-probes.sh 编译出来）
    static var probe: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // RimeKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根目录
            .appending(path: "tools/vm/rime-type-probe")
    }

    static func build(_ dir: URL) throws -> ShellResult {
        try Shell.run(squirrel + "/MacOS/rime_deployer",
                      ["--build", dir.path, squirrel + "/SharedSupport", dir.appending(path: "build").path])
    }

    struct ProbeMissing: Error, CustomStringConvertible {
        var description: String { "找不到 tools/vm/rime-type-probe，先运行 ./tools/vm/build-probes.sh" }
    }

    /// 编码 → 候选（自动上屏的字放在第一个）
    static func type(_ dir: URL, schema: String, _ codes: [String]) throws -> [String: [String]] {
        guard FileManager.default.isExecutableFile(atPath: probe.path) else { throw ProbeMissing() }
        let r = try Shell.run(probe.path, [dir.path, schema] + codes)
        var result: [String: [String]] = [:]
        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            var rest = String(parts[1])
            var candidates: [String] = []
            let committed = "[上屏]"
            if rest.hasPrefix(committed) {
                let after = rest.dropFirst(committed.count)
                if let space = after.firstIndex(of: " ") {
                    candidates.append(String(after[..<space]))
                    rest = String(after[after.index(after: space)...])
                } else {
                    candidates.append(String(after))
                    rest = ""
                }
            }
            if !rest.isEmpty { candidates += rest.components(separatedBy: " | ") }
            result[String(parts[0])] = candidates
        }
        return result
    }
}
