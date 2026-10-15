import Foundation

/// 两份清单比，变了什么（在线方案清单设计 4.2、4.4）：检查更新时告诉用户；正在用的包规则变了要重新应用
public struct CatalogDiff: Sendable, Equatable {
    /// 新增的方案（下架的包里的不算）
    public let addedSchemas: [SchemaSpec]
    /// 正在用的包里，安装规则变了的（包名）
    public let changedInUse: [String]
    /// 这次新标成下架的包（包名）
    public let newlyDeprecated: [String]

    /// inUse：正在用的包 id
    public init(old: Catalog, new: Catalog, inUse: Set<String>) {
        let oldSchemas = Set(old.packages.flatMap(\.schemas).map(\.id))
        addedSchemas = new.packages.filter { !$0.deprecated }.flatMap(\.schemas).filter { !oldSchemas.contains($0.id) }
        changedInUse = new.packages.filter { p in
            guard inUse.contains(p.id), let before = old.package(p.id) else { return false }
            return !p.sameRules(as: before)
        }.map(\.name)
        newlyDeprecated = new.packages.filter { $0.deprecated && old.package($0.id)?.deprecated == false }.map(\.name)
    }

    public var affectsInUse: Bool { !changedInUse.isEmpty }

    /// 给人看的说明
    public var lines: [String] {
        var lines: [String] = []
        if !addedSchemas.isEmpty {
            lines.append("新增方案：" + addedSchemas.map(\.name).joined(separator: "、"))
        }
        if !changedInUse.isEmpty {
            lines.append("你在用的这些方案包的安装规则变了：" + changedInUse.joined(separator: "、") + "。应用改动后生效")
        }
        if !newlyDeprecated.isEmpty {
            lines.append("这些方案包下架了（已经在用的照常能用）：" + newlyDeprecated.joined(separator: "、"))
        }
        if lines.isEmpty { lines.append("方案没有变化（只更新了说明文字等）") }
        return lines
    }
}
