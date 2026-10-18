import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

/// 发布包里没有 rimectl：应用里显示的提示不能让用户去运行命令（终审 I3）
@MainActor @Suite struct AppWordingTests {
    static let messages = [
        "\(TransferError.noSettings)",
        "\(TransferError.importFailed("坏了", previous: "/p/x.zip"))",
        "\(ApplyError.writeFailed("磁盘满了", restored: false, backupID: "b1"))",
        "\(RestoreError.failed("磁盘满了", safetyBackupID: "b2", rolledBack: false))",
        "Rime 目录里的 personal.dict.yaml 在应用外改过，导出的是应用里保存的版本。要带上外面的修改，先运行 rimectl apply --adopt-personal",
        "文本替换的短语也回到了备份时的样子；需要的话重新同步（rimectl textreplacement sync）",
    ]

    @Test func 消息里不出现命令行() {
        let notice = Notice(kind: .error, title: "x", lines: Self.messages)
        #expect(notice.lines.allSatisfy { !$0.contains("rimectl") }, "\(notice.lines)")
        #expect(notice.lines[1].contains("另存在 /p/x.zip，需要时可以在「导入导出」页导入这个文件找回"))
        #expect(notice.lines[2].contains("「备份」页还原 b1"))
        #expect(notice.lines[4].contains("采用外面改过的个人词库"))
    }

    @Test func 引导里的失败也不出现命令行() {
        #expect(!SetupFlow.failure(TransferError.importFailed("坏了", previous: "/p/x.zip")).contains("rimectl"))
    }
}

/// 诊断页：Doctor 的「下一步」是按 rimectl 写的，应用里按检查项换成界面上的做法
@MainActor @Suite struct DiagnosticHintTests {
    typealias W = AppWording

    func hint(_ name: String, _ level: CheckLevel, _ message: String, _ hint: String?) -> String? {
        W.diagnosticHint(DoctorCheck(name: name, level: level, message: message, hint: hint))
    }

    @Test func Doctor里的每条提示都换掉() {
        let cases: [(String, CheckLevel, String, String, String)] = [
            ("鼠须管", .problem, "还没有安装", "运行 rimectl install", "rime.im"),
            ("鼠须管进程", .warning, "没在运行", "运行 rimectl activate", "切换到鼠须管"),
            ("输入法", .problem, "系统里没有鼠须管的输入源", "运行 rimectl activate（会重新注册输入源）", "注销再登录"),
            ("输入法", .problem, "还没有在系统设置里添加鼠须管", "运行 rimectl activate", "系统设置 → 键盘 → 输入法"),
            ("输入法", .warning, "已添加，但现在选中的不是鼠须管", "运行 rimectl activate，或按输入法切换键", "切换键"),
            ("Rime 目录", .warning, "鼠须管还没部署过", "运行 rimectl activate", "切换到鼠须管"),
            ("设置", .warning, "还没有设置", "运行 rimectl settings init rime-ice|flypy|wubi-pinyin", "按引导"),
            ("应用管理的配置", .warning, "还没应用过设置", "运行 rimectl apply", "「应用改动」"),
            ("应用管理的配置", .warning, "有 2 个文件在应用外被改过或删了", "运行 rimectl status 看是哪些；rimectl apply 会先问你", "列出这些文件"),
            ("文本替换", .warning, "打开了同步，但还没同步过", "运行 rimectl textreplacement sync", "「文本替换」页"),
            ("文本替换", .warning, "有变化没同步：新增 1 条，删掉 0 条", "运行 rimectl textreplacement sync", "「文本替换」页"),
        ]
        for (name, level, message, original, expected) in cases {
            let result = hint(name, level, message, original)
            #expect(result?.contains(expected) == true, "\(name)：\(result ?? "nil")")
            #expect(result?.contains("rimectl") == false, "\(name)：\(result ?? "nil")")
        }
    }

    @Test func 不提rimectl的提示原样留着_对不上的不显示() {
        #expect(hint("鼠须管", .ok, "已安装", nil) == nil)
        #expect(hint("新检查", .warning, "x", "重新打开应用") == "重新打开应用")
        #expect(hint("新检查", .warning, "x", "运行 rimectl something") == nil)
    }

    @Test func 诊断页显示的提示没有命令行() async throws {
        let m = try TransferFixtures.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())   // 假电脑没有装鼠须管
        await model.runDiagnostics()
        #expect(!model.checks.isEmpty)
        #expect(model.checks.allSatisfy { !($0.hint ?? "").contains("rimectl") }, "\(model.checks)")
        #expect(model.checks.contains { $0.hint?.contains("rime.im") == true }, "\(model.checks)")
    }
}
