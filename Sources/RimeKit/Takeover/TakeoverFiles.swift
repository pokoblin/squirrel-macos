import Foundation
import Yams

/// 接管时读 Rime 目录里的文件
enum TakeoverFiles {
    /// 文件不存在时返回 nil
    static func read(_ dir: URL, _ path: String) throws -> String? {
        let url = dir.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try TextFile.read(url)
    }

    static func patch(_ text: String, file: String) throws -> Patch {
        do {
            return try Patch.parse(customYAML: text)
        } catch {
            throw TakeoverError.badYAML(file: file, message: String(describing: error))
        }
    }

    static func yaml(_ text: String, file: String) throws -> Node? {
        do {
            return try YAMLNode.parse(text)
        } catch {
            throw TakeoverError.badYAML(file: file, message: String(describing: error))
        }
    }

    /// 词库文件头里的 import_tables（头在第一行 "..." 之前）；读不懂时返回 nil
    static func importTables(_ dictText: String) -> [String]? {
        var header: [Substring] = []
        for line in dictText.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "..." { break }
            header.append(line)
        }
        guard let root = try? YAMLNode.parse(header.joined(separator: "\n")) else { return nil }
        return root["import_tables"]?.sequence?.compactMap(\.string) ?? []
    }
}
