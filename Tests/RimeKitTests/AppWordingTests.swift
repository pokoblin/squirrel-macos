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
