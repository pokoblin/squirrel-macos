import Foundation
import RimeKit

/// 应用什么时候联网（在线方案清单设计 4.6）：「诊断」页和「检查方案清单更新」按钮下面的说明
public enum NetworkUse {
    public struct Row: Sendable, Equatable {
        public let when: String
        public let host: String
        public let what: String
    }

    public static let catalogCheckNote = "会连接 GitHub（raw.githubusercontent.com），只下载方案清单，不上传任何内容。清单带签名，验不过就不用。"

    public static let rows: [Row] = [
        Row(when: "安装、更新鼠须管", host: "GitHub（api.github.com、github.com 和它的下载服务器）", what: "鼠须管安装包"),
        Row(when: "安装、更新方案，导入", host: "GitHub（api.github.com、codeload.github.com、github.com 和它的下载服务器）", what: "方案文件"),
        Row(when: "点「检查方案清单更新」，或导入时遇到不认识的方案", host: "GitHub（raw.githubusercontent.com）", what: "方案清单"),
    ]

    public static let footer = "以上都只下载，不上传你的设置、词库、短语或文本替换。除此以外应用不联网。"

    /// 现在用的是哪份方案清单
    public static func catalogSource(_ status: CatalogStatus) -> String {
        switch status.origin {
        case .builtIn:
            return "现在用的是应用内置的方案清单（编号 \(status.catalog.serial)）"
        case .online(let date):
            return "现在用的是在线方案清单（编号 \(status.catalog.serial)，\(date.formatted(date: .numeric, time: .omitted)) 下载）"
        }
    }
}
