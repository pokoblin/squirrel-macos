import Foundation

public enum CatalogError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormat(Int)
    case duplicatePackageID(String)
    case duplicateSchemaID(String)
    case unknownDependency(package: String, dependency: String)
    case dependencyCycle([String])
    case requiredFileNotIncluded(package: String, file: String)
    case unknownPackage(String)
    case builtInMissing

    public var description: String {
        switch self {
        case .unsupportedFormat(let v):
            return "方案清单的格式版本是 \(v)，这个版本的应用只认识 \(Catalog.supportedFormatVersion)，请更新应用"
        case .duplicatePackageID(let id):
            return "方案清单里有两个包都叫 \(id)"
        case .duplicateSchemaID(let id):
            return "方案清单里有两个方案都叫 \(id)"
        case .unknownDependency(let package, let dependency):
            return "包 \(package) 依赖的 \(dependency) 不在方案清单里"
        case .dependencyCycle(let path):
            return "方案清单里有循环依赖：\(path.joined(separator: " → "))"
        case .requiredFileNotIncluded(let package, let file):
            return "包 \(package) 的必需文件 \(file) 不在安装规则里，永远装不上"
        case .unknownPackage(let id):
            return "清单里没有这个包：\(id)"
        case .builtInMissing:
            return "应用里找不到内置的方案清单 catalog.json"
        }
    }
}
