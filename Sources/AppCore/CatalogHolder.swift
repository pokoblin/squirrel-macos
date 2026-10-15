import Foundation
import RimeKit

/// 生效的方案清单。引导、主窗口共用一个：导入或检查更新换了清单，大家都看到新的
public final class CatalogHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var current: CatalogStatus

    public init(_ status: CatalogStatus) {
        current = status
    }

    public var status: CatalogStatus { lock.withLock { current } }

    public func update(_ status: CatalogStatus) {
        lock.withLock { current = status }
    }
}
