import Foundation

public enum TextFileError: Error, Equatable, Sendable, CustomStringConvertible {
    case notUTF8(String)

    public var description: String {
        switch self {
        case .notUTF8(let path):
            return "\((path as NSString).lastPathComponent) 不是 UTF-8 编码的文本，读不了。请用文本编辑器另存为 UTF-8 再试（\(path)）"
        }
    }
}

/// 读配置、短语这类文本文件：不是 UTF-8 时说清楚是哪个文件
public enum TextFile {
    public static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw TextFileError.notUTF8(url.path) }
        return text
    }
}
