import Foundation
import Yams

public enum TakeoverError: Error, Equatable, Sendable, CustomStringConvertible {
    case alreadyManaged
    case settingsExist(String)
    case nothingRecognized
    case badYAML(file: String, message: String)
    case missingPackage(String)

    public var description: String {
        switch self {
        case .alreadyManaged:
            return "这个 Rime 目录已经由应用管理了（ledger.json 里有记录），不用再接管"
        case .settingsExist(let path):
            return "已经有设置了：\(path)。接管会覆盖设置和个人内容，要覆盖就加 --force"
        case .nothingRecognized:
            return "Rime 目录里的配置没有一个方案在方案清单里，认不出来。可以选一个起步方案（rimectl settings init …）再应用，原来的文件会先备份"
        case let .badYAML(file, message):
            return "读不懂 \(file)：\(message)"
        case .missingPackage(let id):
            return "缺少包 \(id)，请先下载"
        }
    }
}

/// 第一眼：Rime 目录里有没有配置、方案列表里有哪些方案、要下载哪些包做对照（设计 6.2）。不需要上游包。
public struct TakeoverSurvey: Sendable, Equatable {
    /// 没有配置文件（目录不存在，或者只有 Rime 自己的运行文件）
    public let isEmpty: Bool
    /// 方案列表里清单认识的方案，按原来的顺序（去重）
    public let schemas: [String]
    /// 方案列表里清单不认识的方案：接管后不启用，文件原样保留
    public let unknownSchemas: [String]
    /// 认识的方案所属的包，按第一次出现的顺序
    public let packages: [String]

    public init(isEmpty: Bool, schemas: [String], unknownSchemas: [String], packages: [String]) {
        self.isEmpty = isEmpty
        self.schemas = schemas
        self.unknownSchemas = unknownSchemas
        self.packages = packages
    }

    public static func scan(_ rime: URL, catalog: Catalog) throws -> TakeoverSurvey {
        guard !(try RimeFiles.configFiles(in: rime)).isEmpty else {
            return TakeoverSurvey(isEmpty: true, schemas: [], unknownSchemas: [], packages: [])
        }
        var schemas: [String] = []
        var unknown: [String] = []
        var packages: [String] = []
        for id in try schemaList(rime.resolvingSymlinksInPath()) {
            if let package = catalog.packageOwning(schema: id) {
                if !schemas.contains(id) { schemas.append(id) }
                if !packages.contains(package.id) { packages.append(package.id) }
            } else if !unknown.contains(id) {
                unknown.append(id)
            }
        }
        return TakeoverSurvey(isEmpty: false, schemas: schemas, unknownSchemas: unknown, packages: packages)
    }

    /// 方案列表：default.custom.yaml 补丁里的 schema_list 优先，没有就看 default.yaml
    static func schemaList(_ dir: URL) throws -> [String] {
        if let text = try TakeoverFiles.read(dir, "default.custom.yaml"),
           let list = PatchLeaves(try TakeoverFiles.patch(text, file: "default.custom.yaml"))["schema_list"] {
            return ids(list)
        }
        if let text = try TakeoverFiles.read(dir, "default.yaml"),
           let list = try TakeoverFiles.yaml(text, file: "default.yaml")?["schema_list"] {
            return ids(list)
        }
        return []
    }

    static func ids(_ list: Node) -> [String] {
        (list.sequence ?? []).compactMap { $0["schema"]?.string }
    }
}
