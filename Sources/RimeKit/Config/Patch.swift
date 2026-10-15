import Foundation
import Yams

/// 造 YAML 节点的小工具
public enum YAMLNode {
    public static func text(_ s: String) -> Node { Node(s) }
    public static func int(_ n: Int) -> Node { Node(String(n)) }
    public static func bool(_ b: Bool) -> Node { Node(b ? "true" : "false") }

    public static func map(_ pairs: [(String, Node)]) -> Node {
        .mapping(Node.Mapping(pairs.map { (Node($0.0), $0.1) }))
    }

    public static func list(_ items: [Node]) -> Node {
        .sequence(Node.Sequence(items))
    }

    /// 读一段 YAML；空文本返回 nil
    public static func parse(_ text: String) throws -> Node? {
        try Yams.compose(yaml: text)
    }
}

/// 一份 Rime 补丁，也就是 xxx.custom.yaml 里 `patch:` 下面的内容。
/// 键按加入的顺序保留。Rime 按顺序应用补丁、后面的覆盖前面的，
/// 所以同一个键再写一次时，删掉旧的、把新的放到最后。
public struct Patch: Equatable {
    public struct Entry: Equatable {
        public let key: String
        public let value: Node
    }

    public static let header = "# 由 squirrel-macos 生成。请在应用里修改设置；直接改这个文件，下次应用时会被覆盖。\n"

    public private(set) var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public subscript(key: String) -> Node? {
        entries.last { $0.key == key }?.value
    }

    public mutating func set(_ key: String, _ value: Node) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, value: value))
    }

    public mutating func merge(_ other: Patch) {
        for entry in other.entries { set(entry.key, entry.value) }
    }

    /// 从 xxx.custom.yaml 的全文读出补丁；没有 patch 段时得到空补丁
    public static func parse(customYAML text: String) throws -> Patch {
        var patch = Patch()
        guard let root = try YAMLNode.parse(text), let mapping = root["patch"]?.mapping else { return patch }
        for (key, value) in mapping {
            guard let name = key.string else { continue }
            patch.set(name, value)
        }
        return patch
    }

    /// 生成 xxx.custom.yaml 的全文（带说明头）
    public func renderCustomYAML() throws -> String {
        let body = Node.mapping(Node.Mapping(entries.map { (Node($0.key), $0.value) }))
        let root = YAMLNode.map([("patch", body)])
        return Self.header + (try Yams.serialize(node: root, allowUnicode: true))
    }
}
