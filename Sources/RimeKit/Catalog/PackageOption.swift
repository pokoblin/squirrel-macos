import Foundation

/// 包的可选项，例如极点五笔的「拼音词库」：用自带的还是雾凇大词库
public struct PackageOption: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let defaultChoice: String
    public let choices: [OptionChoice]

    public func choice(_ id: String) -> OptionChoice? {
        choices.first { $0.id == id }
    }
}

public struct OptionChoice: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    /// 选了这一项要额外用到的包
    public let dependencies: [String]
    /// 选了这一项要由应用生成的总词库
    public let generatedDicts: [GeneratedDict]
    /// 方案 id → 补丁键 → 值，写进 <方案>.custom.yaml
    public let patches: [String: [String: String]]
}

/// 只写 import_tables 的总词库，例如 pinyin_ext.dict.yaml
public struct GeneratedDict: Sendable, Equatable, Codable {
    public let name: String
    public let importTables: [ImportTable]
}

public struct ImportTable: Sendable, Equatable, Codable {
    public let name: String
    /// true：只有用户有这个名字的个人词库时才挂上
    public let onlyIfPersonal: Bool

    public init(name: String, onlyIfPersonal: Bool) {
        self.name = name
        self.onlyIfPersonal = onlyIfPersonal
    }

    private enum CodingKeys: String, CodingKey { case name, onlyIfPersonal }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        onlyIfPersonal = try c.decodeIfPresent(Bool.self, forKey: .onlyIfPersonal) ?? false
    }
}
