import Darwin
import Foundation

/// 安装文件的匹配规则，路径都是相对包根目录的。
/// - `*`、`?`、`[...]` 不跨目录：`*.schema.yaml` 只匹配根目录下的文件
/// - 以 `/**` 结尾：这个目录下任意深度的所有文件，例如 `lua/**`
public struct FileGlob: Sendable, Equatable, Codable {
    public let pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern
    }

    public func matches(_ relativePath: String) -> Bool {
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(2))   // 留下结尾的 "/"
            return relativePath.hasPrefix(prefix) && relativePath.count > prefix.count
        }
        return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
    }

    public init(from decoder: any Decoder) throws {
        pattern = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(pattern)
    }
}
