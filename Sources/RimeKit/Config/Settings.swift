import Foundation

/// 用户在应用里做的所有选择（设计第 5 节）
public struct Settings: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// 启用的方案，按顺序；第一个是默认方案
    public var schemas: [String]
    /// 包 id → 选项 id → 选的哪一项；没写的用清单里的默认值
    public var options: [String: [String: String]]
    public var appearance: Appearance
    public var textReplacement: TextReplacementSettings
    /// 接管时认不出的补丁项，按文件名（不带 .custom.yaml）存，生成时原样写回
    public var preservedPatches: [String: [PreservedPatch]]

    public init(
        schemas: [String],
        options: [String: [String: String]] = [:],
        appearance: Appearance = Appearance(),
        textReplacement: TextReplacementSettings = TextReplacementSettings(),
        preservedPatches: [String: [PreservedPatch]] = [:]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.schemas = schemas
        self.options = options
        self.appearance = appearance
        self.textReplacement = textReplacement
        self.preservedPatches = preservedPatches
    }

    public func validate(_ catalog: Catalog) throws {
        guard formatVersion == Self.currentFormatVersion else { throw SettingsError.unsupportedFormat(formatVersion) }
        guard !schemas.isEmpty else { throw SettingsError.noSchemas }
        var seen = Set<String>()
        for schema in schemas {
            guard seen.insert(schema).inserted else { throw SettingsError.duplicateSchema(schema) }
            guard catalog.packageOwning(schema: schema) != nil else { throw SettingsError.unknownSchema(schema) }
        }
        for (packageID, chosen) in options.sorted(by: { $0.key < $1.key }) {
            let package = catalog.package(packageID)
            for (optionID, choiceID) in chosen.sorted(by: { $0.key < $1.key }) {
                guard let option = package?.options.first(where: { $0.id == optionID }) else {
                    throw SettingsError.unknownOption(package: packageID, option: optionID)
                }
                guard option.choice(choiceID) != nil else {
                    throw SettingsError.unknownChoice(package: packageID, option: optionID, choice: choiceID)
                }
            }
        }
        try Self.check("候选字字号", appearance.fontPoint, 8...72)
        try Self.check("序号字号", appearance.labelFontPoint, 8...72)
        try Self.check("注释字号", appearance.commentFontPoint, 8...72)
        try Self.check("每页候选数", appearance.pageSize, 1...10)
    }

    /// 这个包的这个选项现在选的是哪一项（没选就是默认值）
    public func choice(_ option: PackageOption, of package: PackageSpec) -> OptionChoice {
        let id = options[package.id]?[option.id] ?? option.defaultChoice
        return option.choice(id) ?? option.choice(option.defaultChoice) ?? option.choices[0]
    }

    /// 要用到的包：启用的方案所属的包 + 所选选项的依赖；依赖（包括选项的依赖）在前
    public func requiredPackages(_ catalog: Catalog) throws -> [PackageSpec] {
        var ids: [String] = []
        for schema in schemas {
            guard let package = catalog.packageOwning(schema: schema) else { throw SettingsError.unknownSchema(schema) }
            if !ids.contains(package.id) { ids.append(package.id) }
        }
        var optionDependencies: [String] = []
        for id in ids {
            guard let package = catalog.package(id) else { continue }
            for option in package.options {
                for d in choice(option, of: package).dependencies where !optionDependencies.contains(d) {
                    optionDependencies.append(d)
                }
            }
        }
        return try catalog.installOrder(for: optionDependencies + ids)
    }

    /// 起步方案（设计 6.2：~/Library/Rime 是空的时候让用户选一个）
    public static func starter(_ starter: Starter) -> Settings {
        switch starter {
        case .rimeIce:
            return Settings(schemas: ["rime_ice"])
        case .flypy:
            return Settings(schemas: ["double_pinyin_flypy"])
        case .wubiPinyin:
            return Settings(
                schemas: ["wubi86_jidian_pinyin", "wubi86_jidian", "numbers",
                          "wubi86_jidian_trad", "wubi86_jidian_trad_pinyin", "pinyin_simp"],
                options: ["wubi86-jidian": ["pinyinDictionary": "rime-ice"]])
        }
    }

    private static func check(_ field: String, _ value: Int?, _ range: ClosedRange<Int>) throws {
        if let value, !range.contains(value) { throw SettingsError.outOfRange(field: field, value: value, range: range) }
    }
}

public struct Appearance: Sendable, Equatable, Codable {
    public var colorScheme: String?
    public var colorSchemeDark: String?
    public var fontPoint: Int?
    public var labelFontPoint: Int?
    public var commentFontPoint: Int?
    public var candidateListLayout: CandidateListLayout?
    public var textOrientation: TextOrientation?
    public var pageSize: Int?

    public init(
        colorScheme: String? = nil, colorSchemeDark: String? = nil,
        fontPoint: Int? = nil, labelFontPoint: Int? = nil, commentFontPoint: Int? = nil,
        candidateListLayout: CandidateListLayout? = nil, textOrientation: TextOrientation? = nil,
        pageSize: Int? = nil
    ) {
        self.colorScheme = colorScheme
        self.colorSchemeDark = colorSchemeDark
        self.fontPoint = fontPoint
        self.labelFontPoint = labelFontPoint
        self.commentFontPoint = commentFontPoint
        self.candidateListLayout = candidateListLayout
        self.textOrientation = textOrientation
        self.pageSize = pageSize
    }
}

public enum CandidateListLayout: String, Sendable, Equatable, Codable {
    case stacked, linear
}

public enum TextOrientation: String, Sendable, Equatable, Codable {
    case horizontal, vertical
}

public struct TextReplacementSettings: Sendable, Equatable, Codable {
    public var sync: Bool
    /// 上次同步时文本替换内容的哈希（只存哈希，不存内容）
    public var lastSyncedHash: String?

    public init(sync: Bool = false, lastSyncedHash: String? = nil) {
        self.sync = sync
        self.lastSyncedHash = lastSyncedHash
    }
}

public struct PreservedPatch: Sendable, Equatable, Codable {
    public var key: String
    /// 这个键的值的 YAML 原文
    public var yaml: String

    public init(key: String, yaml: String) {
        self.key = key
        self.yaml = yaml
    }
}

public enum Starter: String, CaseIterable, Sendable {
    case rimeIce = "rime-ice"
    case flypy
    case wubiPinyin = "wubi-pinyin"

    public var displayName: String {
        switch self {
        case .rimeIce: return "雾凇拼音（全拼）"
        case .flypy: return "小鹤双拼"
        case .wubiPinyin: return "五笔 + 拼音混输"
        }
    }
}

public enum SettingsError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormat(Int)
    case noSchemas
    case unknownSchema(String)
    case duplicateSchema(String)
    case unknownOption(package: String, option: String)
    case unknownChoice(package: String, option: String, choice: String)
    case outOfRange(field: String, value: Int, range: ClosedRange<Int>)

    public var description: String {
        switch self {
        case .unsupportedFormat(let v):
            return "设置文件的格式版本是 \(v)，这个版本的应用只认识 \(Settings.currentFormatVersion)，请更新应用"
        case .noSchemas:
            return "至少要启用一个输入方案"
        case .unknownSchema(let id):
            return "方案清单里没有这个方案：\(id)"
        case .duplicateSchema(let id):
            return "方案 \(id) 重复启用了"
        case let .unknownOption(package, option):
            return "包 \(package) 没有选项 \(option)"
        case let .unknownChoice(package, option, choice):
            return "包 \(package) 的选项 \(option) 没有「\(choice)」这一项"
        case let .outOfRange(field, value, range):
            return "\(field)是 \(value)，应该在 \(range.lowerBound) 到 \(range.upperBound) 之间"
        }
    }
}
