import Foundation

/// RimeKit 的提示是应用和 rimectl 共用的，里面有让人运行 rimectl 的说法；发布包里没有 rimectl，
/// 应用里显示前换成界面上的做法（Notice 和引导的失败页都经过这里）
public enum AppWording {
    static let replacements: [(pattern: String, template: String)] = [
        (#"先 rimectl takeover 接管已有配置，或 rimectl settings init 选一个起步方案"#, "请退出应用再打开，按引导选起步方案或接管已有配置"),
        (#"需要时可以用 rimectl import 这个文件找回"#, "需要时可以在「导入导出」页导入这个文件找回"),
        (#"请用 rimectl restore (\S+) 手动还原"#, "请到「备份」页还原 $1"),
        (#"请用 rimectl restore (\S+) 再试"#, "请到「备份」页还原 $1 再试"),
        (#"先运行 rimectl apply --adopt-personal"#, "先在「应用改动」时选「采用外面改过的个人词库」"),
        (#"（rimectl textreplacement sync）"#, "（「文本替换」页里同步）"),
        (#"可以先运行 rimectl catalog check 检查方案清单更新"#, "可以先到「方案」页点「检查方案清单更新」"),
    ]

    public static func forApp(_ text: String) -> String {
        replacements.reduce(text) { result, item in
            result.replacingOccurrences(of: item.pattern, with: item.template, options: .regularExpression)
        }
    }
}
