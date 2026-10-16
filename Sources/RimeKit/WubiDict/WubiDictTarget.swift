import Foundation

/// 五笔词库编辑器编辑的是哪个包、哪些文件
public struct WubiDictTarget: Sendable, Equatable {
    public var packageID: String
    /// 主词库文件名（只读）
    public var mainDict: String
    /// 个人词库文件名（唯一会改的文件）
    public var userDict: String
    /// 方案 id 的前缀：以它开头的方案用这套词库
    public var schemaPrefix: String

    public init(packageID: String, mainDict: String, userDict: String, schemaPrefix: String) {
        self.packageID = packageID
        self.mainDict = mainDict
        self.userDict = userDict
        self.schemaPrefix = schemaPrefix
    }

    /// 极点五笔 86
    public static let jidian = WubiDictTarget(
        packageID: "wubi86-jidian", mainDict: "wubi86_jidian.dict.yaml",
        userDict: "wubi86_jidian_user.dict.yaml", schemaPrefix: "wubi86_jidian")

    /// 个人词库在 `import_tables` 里的名字（文件名去掉 `.dict.yaml`）
    public var userTable: String { Self.tableName(userDict) }

    static func tableName(_ fileName: String) -> String {
        fileName.hasSuffix(".dict.yaml") ? String(fileName.dropLast(".dict.yaml".count)) : fileName
    }
}
