import Foundation

/// 给界面看的一条消息：结果、错误，可以带一个下一步的按钮
public struct Notice: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case info, warning, error
    }

    public enum Action: Equatable, Sendable {
        /// 下载失败时：用本地缓存的旧版本再应用一次
        case applyUsingCache
        /// 部署有问题时：还原到这个备份
        case restore(String)
    }

    public let id = UUID()
    public var kind: Kind
    public var title: String
    public var lines: [String]
    public var action: Action?
    public var actionTitle: String?

    public init(kind: Kind, title: String, lines: [String], action: Action? = nil, actionTitle: String? = nil) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.action = action
        self.actionTitle = actionTitle
    }
}
