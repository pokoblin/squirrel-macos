import Foundation

public struct GenerationInput: Sendable {
    public var settings: Settings
    public var catalog: Catalog
    /// 包 id → 缓存
    public var packages: [String: CachedPackage]
    public var personal: PersonalContent
    /// 从 macOS 文本替换生成的短语（阶段 7 接上；现在传空）
    public var textReplacementPhrases: [Phrase]

    public init(settings: Settings, catalog: Catalog, packages: [String: CachedPackage],
                personal: PersonalContent, textReplacementPhrases: [Phrase]) {
        self.settings = settings
        self.catalog = catalog
        self.packages = packages
        self.personal = personal
        self.textReplacementPhrases = textReplacementPhrases
    }
}

public enum FileOrigin: Sendable, Equatable {
    case package(String)
    case generated
    case personal
}

public struct GeneratedFile: Sendable, Equatable {
    public let path: String
    public let origin: FileOrigin
}

public struct GenerationResult: Sendable, Equatable {
    /// 写出的所有文件，按路径排序（阶段 3 记进 ledger）
    public let files: [GeneratedFile]
    public let warnings: [String]
}

public enum GenerationError: Error, Equatable, Sendable, CustomStringConvertible {
    case outputNotEmpty(String)
    case missingPackage(String)
    case badYAML(file: String, message: String)

    public var description: String {
        switch self {
        case .outputNotEmpty(let path):
            return "输出目录不是空的：\(path)。生成配置只往空目录里写"
        case .missingPackage(let id):
            return "缺少包 \(id)，请先下载"
        case let .badYAML(file, message):
            return "读不懂 \(file)：\(message)"
        }
    }
}

/// 设置 + 上游包 + 个人内容 → 一份完整的 Rime 用户目录。
/// 只往一个空目录里写；规则见阶段 2 计划「生成规则」一节和设计文档。
public struct ConfigGenerator: Sendable {
    public init() {}

    public func generate(_ input: GenerationInput, into output: URL) throws -> GenerationResult {
        try input.settings.validate(input.catalog)
        let context = try GenerationContext(input: input, output: output)
        try context.copyPackageFiles()
        try context.collectUpstreamPatches()
        try context.applyPreservedPatches()
        context.applySchemaList()
        try context.applyAppearance()
        try context.writePatches()
        return context.result()
    }
}
