import Foundation
import RimeKit

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
        (#"可以先运行 rimectl catalog check 检查方案清单更新"#, "可以先到「方案」页点「检查更新」"),
    ]

    public static func forApp(_ text: String) -> String {
        replacements.reduce(text) { result, item in
            result.replacingOccurrences(of: item.pattern, with: item.template, options: .regularExpression)
        }
    }

    /// 诊断页的「下一步」：Doctor 按 rimectl 写，同一句「运行 rimectl activate」在不同检查项里要做的事不一样，
    /// 所以按检查项换。对不上、又提到 rimectl 的不显示（不能让用户去运行发布包里没有的命令）
    public static func diagnosticHint(_ check: DoctorCheck) -> String? {
        guard let hint = check.hint else { return nil }
        guard hint.contains("rimectl") else { return hint }
        switch check.name {
        case "鼠须管":
            return "从鼠须管官网 rime.im 下载安装，装好后回到这里点「重新检查」"
        case "鼠须管进程", "Rime 目录":
            return "切换到鼠须管打几个字，它会自己启动并部署"
        case "输入法":
            if check.message.contains("没有鼠须管的输入源") {
                return "注销再登录一次；还不行的话，从鼠须管官网 rime.im 重新下载安装"
            }
            if check.message.contains("还没有在系统设置里添加") {
                return "在「系统设置 → 键盘 → 输入法」里添加鼠须管"
            }
            return "按输入法切换键切到鼠须管"
        case "设置":
            return "请退出应用再打开，按引导选起步方案或接管已有配置"
        case "应用管理的配置":
            return check.message.hasPrefix("还没应用过")
                ? "改完设置后点「应用改动」"
                : "点「应用改动」时会列出这些文件，问你怎么处理"
        case "文本替换":
            return "到「文本替换」页同步"
        default:
            return nil
        }
    }
}
