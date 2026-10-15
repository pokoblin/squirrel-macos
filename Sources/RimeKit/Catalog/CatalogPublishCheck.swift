import Foundation

/// 发布在线清单前的检查（在线方案清单设计 3.3、5.1）：serial 要变大；包 id、方案 id 只能加，不能删、不能改
public enum CatalogPublishCheck {
    /// old：上一次发布的清单（第一次发布时为 nil）。返回发现的问题，空的表示可以发布
    public static func problems(old: Catalog?, new: Catalog) -> [String] {
        var problems: [String] = []
        if new.serial <= 0 { problems.append("清单要写 serial（正整数，例如 2026101501）") }
        guard let old else { return problems }
        if new.serial > 0, new.serial <= old.serial { problems.append("serial 要比上次发布的 \(old.serial) 大") }
        let packages = Set(new.packages.map(\.id))
        let schemas = Set(new.packages.flatMap(\.schemas).map(\.id))
        for id in old.packages.map(\.id) where !packages.contains(id) {
            problems.append("包 \(id) 不见了：已经发布的包不能删，要下架请标 deprecated")
        }
        for id in old.packages.flatMap(\.schemas).map(\.id) where !schemas.contains(id) {
            problems.append("方案 \(id) 不见了：已经发布的方案不能删、不能改 id")
        }
        return problems
    }
}
