import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct AppInfoTests {
    @Test func 生成的文件头写应用名() {
        // 用户打开 Rime 目录里的文件，要能看出是哪个应用写的
        #expect(Patch.header == "# 由鼠须管助手（squirrel-macos）生成。请在鼠须管助手里修改设置；直接改这个文件，下次应用时会被覆盖。\n")
        #expect(PhraseFile.header.contains("# 由鼠须管助手（squirrel-macos）生成的自定义短语。"))
    }

    @Test func 导出文件的提示写应用名() {
        #expect(TransferError.notAnExport("/x.zip").description == "/x.zip 不是鼠须管助手的导出文件")
        #expect(TransferError.targetNotAFile("/d").description.contains("例如 /d/鼠须管助手-导出.zip"))
    }

    @Test func 改了文件头_已经在用的配置下次应用直接重写_不算外部改动() async throws {
        let m = try TransferFixtures.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        // 模拟旧版本写的文件：磁盘上的内容和账本里的哈希都是旧文件头
        let file = m.locations.rimeDirectory.appending(path: "squirrel.custom.yaml")
        let old = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: Patch.header, with: "# 由 squirrel-macos 生成。请在应用里修改设置；直接改这个文件，下次应用时会被覆盖。\n")
        try Data(old.utf8).write(to: file)
        var ledger = try Ledger.load(m.paths)
        let entry = try #require(ledger.entries["squirrel.custom.yaml"])
        ledger.entries["squirrel.custom.yaml"] = LedgerEntry(sha256: Hashing.sha256(of: Data(old.utf8)), origin: entry.origin)
        try ledger.save(m.paths)
        await model.apply()
        #expect(model.pendingExternalChanges == nil)
        #expect(model.notice?.title == "改动已经生效")
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix(Patch.header))
    }

    @Test func 版本号和Info_plist一致() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "tools/app/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["CFBundleShortVersionString"] as? String == AppInfo.version)
        #expect(AppVersion(AppInfo.version) != nil)
    }
}
