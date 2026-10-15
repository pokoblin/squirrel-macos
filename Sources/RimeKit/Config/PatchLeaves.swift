import Foundation
import Yams

/// 补丁的「叶子」：把映射一层层拆开，得到 路径 → 值（列表、标量、空映射是叶子）。
/// 例：`menu: {page_size: 5}` 拆成 `menu/page_size = 5`。
/// 接管已有配置时，用它逐项比对用户的补丁和上游默认补丁（整段写法和路径写法都能比）。
public struct PatchLeaves: Equatable {
    /// 按第一次出现的顺序
    public private(set) var paths: [String] = []
    private var values: [String: Node] = [:]

    public init() {}

    /// 按顺序应用补丁里的每一项（和 Rime 一样，后面的覆盖前面的）
    public init(_ patch: Patch) {
        for entry in patch.entries { set(entry.key, entry.value) }
    }

    public subscript(path: String) -> Node? { values[path] }

    /// 写入一项：整段写入时先清掉这一段下面原来的叶子；写下层路径时清掉上层原来的值
    public mutating func set(_ key: String, _ value: Node) {
        let stale = paths.filter { $0 == key || $0.hasPrefix(key + "/") || key.hasPrefix($0 + "/") }
        for path in stale { values[path] = nil }
        paths.removeAll { stale.contains($0) }
        for (path, leaf) in Self.flatten(key, value) {
            if values[path] == nil { paths.append(path) }
            values[path] = leaf
        }
    }

    /// 拆一项。映射的键里有 "/"（例如标点映射）或是空的、不是字符串时，整个映射当一个叶子：拆开的路径 Rime 认不出来
    public static func flatten(_ key: String, _ value: Node) -> [(path: String, value: Node)] {
        guard case .mapping(let mapping) = value, !mapping.isEmpty else { return [(key, value)] }
        var names: [(String, Node)] = []
        for (k, v) in mapping {
            guard let name = k.string, !name.isEmpty, !name.contains("/") else { return [(key, value)] }
            names.append((name, v))
        }
        return names.flatMap { flatten("\(key)/\($0.0)", $0.1) }
    }

    /// 两个路径是同一个，或者一个在另一个下面
    public static func overlaps(_ a: String, _ b: String) -> Bool {
        a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
}

extension YAMLNode {
    /// 两个值是不是一样：不管引号风格、映射里键的顺序；列表要顺序一样
    public static func same(_ a: Node, _ b: Node) -> Bool {
        canonical(a) == canonical(b)
    }

    static func canonical(_ node: Node) -> String {
        switch node {
        case .scalar(let scalar):
            return scalar.string.debugDescription
        case .sequence(let sequence):
            return "[" + sequence.map(canonical).joined(separator: ",") + "]"
        case .mapping(let mapping):
            return "{" + mapping.map { canonical($0.key) + ":" + canonical($0.value) }.sorted().joined(separator: ",") + "}"
        case .alias:
            return String(describing: node)
        }
    }
}
