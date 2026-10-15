import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct MainModelActionsTests {
    typealias T = TransferFixtures

    func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    @Test func 应用改动后生效() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.kind == .info)
        #expect(model.notice?.title == "改动已经生效")
        #expect(!model.isDirty)
        #expect(model.saved.appearance.fontPoint == 26)
        #expect(try SettingsStore(paths: m.paths).load()?.appearance.fontPoint == 26)
        #expect(FileManager.default.fileExists(atPath: m.locations.rimeDirectory.appending(path: "squirrel.custom.yaml").path))
        #expect(model.working == nil)
    }

    @Test func 编译不过时什么都不写_草稿还在() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        let model = try MainModel(env: m.environment(compiler: failing))
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.kind == .error)
        #expect(model.notice?.title == "新配置编译不过，没有写入")
        #expect(model.isDirty)
        #expect(try SettingsStore(paths: m.paths).load()?.appearance.fontPoint == 22)
    }

    @Test func 外部改动_放弃和覆盖() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()                                   // 先写一次，ledger 里有记录
        let file = m.locations.rimeDirectory.appending(path: "default.custom.yaml")
        try Data((read(file) + "# 在应用外改过\n").utf8).write(to: file)
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.pendingExternalChanges == [.modified("default.custom.yaml")])
        #expect(!model.pendingPersonalChanges)
        await model.resolveExternalChanges(.cancel)
        #expect(model.pendingExternalChanges == nil)
        #expect(model.isDirty)
        #expect(read(file).contains("在应用外改过"))
        await model.apply()
        await model.resolveExternalChanges(.overwrite)
        #expect(model.notice?.title == "改动已经生效")
        #expect(!read(file).contains("在应用外改过"))
        #expect(!model.isDirty)
    }

    @Test func 外部改过的个人词库可以采用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        let dict = m.locations.rimeDirectory.appending(path: "py_user.dict.yaml")
        let edited = read(dict) + "外面加的\twai mian\t1\n"
        try Data(edited.utf8).write(to: dict)
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.pendingPersonalChanges)
        await model.resolveExternalChanges(.adoptPersonal)
        #expect(model.notice?.title == "改动已经生效")
        #expect(read(m.paths.personalDicts.appending(path: "py_user.dict.yaml")) == edited)
    }

    @Test func 下载失败时可以先用本地旧版本() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        var env = m.environment()
        env.fetchPackage = { _ in throw HTTPError.transport("断网了") }
        let model = try MainModel(env: env)
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.action == .applyUsingCache)
        #expect(model.notice?.lines.joined().contains("断网了") == true)
        #expect(try Ledger.load(m.paths).entries.isEmpty)       // 什么都没写
        await model.perform(.applyUsingCache)
        #expect(model.notice?.title == "改动已经生效")
        #expect(!model.isDirty)
    }

    @Test func 部署有错误时可以还原到应用改动前() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        m.squirrel.errorLine = "E20261015 12:00:00.000000 1 deployer.cc:1] 部署出错"
        model.draft.appearance.fontPoint = 26
        await model.apply()
        guard case .restore(let id)? = model.notice?.action else { Issue.record("\(String(describing: model.notice))"); return }
        #expect(model.notice?.kind == .warning)
        m.squirrel.errorLine = nil
        await model.perform(.restore(id))
        #expect(model.notice?.title.contains("还原") == true)
    }

    @Test func 正在做的时候再点不会重复做() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var value = 0
            func add() { lock.withLock { value += 1 } }
        }
        let fetches = Counter()
        var env = m.environment()
        let fetch = env.fetchPackage
        env.fetchPackage = { spec in
            fetches.add()
            try? await Task.sleep(for: .milliseconds(50))
            return try await fetch(spec)
        }
        let model = try MainModel(env: env)
        model.draft.appearance.fontPoint = 26
        async let first: Void = model.apply()
        async let second: Void = model.apply()
        _ = await (first, second)
        #expect(fetches.value == 3)            // 只应用了一次：要用 words、wubi、pinyin 三个包
        #expect(m.squirrel.calls.count == 1)   // 只部署了一次
    }

    final class Replacements: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [Phrase]
        init(_ phrases: [Phrase]) { value = phrases }
        func set(_ phrases: [Phrase]) { lock.withLock { value = phrases } }
        func get() -> TextReplacementSnapshot {
            lock.withLock { TextReplacementSnapshot(usable: value, badShortcut: 1, badPhrase: 0) }
        }
    }

    @Test func 文本替换检查() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let a = Phrase(text: "替换甲", code: "tha", weight: 1)
        let b = Phrase(text: "替换乙", code: "thb", weight: 1)
        let r = Replacements([a])
        let model = try MainModel(env: m.environment(textReplacements: { r.get() }))
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus == TextReplacementStatus(usable: 1, badShortcut: 1, badPhrase: 0, changes: nil, synced: false, error: nil))
        model.draft.textReplacement.sync = true
        await model.apply()
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus?.changes == TextReplacementSync.Changes(added: 0, removed: 0))
        r.set([a, b])
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus?.changes == TextReplacementSync.Changes(added: 1, removed: 0))
        #expect(model.textReplacementStatus?.synced == true)
    }

    @Test func 导出() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        let file = m.dir.url.appending(path: "out/e.zip")
        await model.export(to: file)
        #expect(model.notice?.title == "已导出")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(m.tool.calls == ["export wb_py"])
        model.includeUserDB = false
        await model.export(to: file)
        #expect(m.tool.calls == ["export wb_py"])   // 这次没导输入习惯
    }

    @Test func 导入后界面上的设置换成导入的() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        let b = try T.machine(userDB: [:]); defer { b.dir.remove() }
        try SettingsStore(paths: b.paths).save(Settings(schemas: ["py"]))
        let model = try MainModel(env: b.environment())
        model.setEnabled("wb", true)                 // 还没应用的改动也会被换掉
        await model.importFile(file)
        #expect(model.saved == T.settings)
        #expect(model.draft == T.settings)
        #expect(model.notice?.lines.contains { $0.contains("另存在") } == true)
    }

    @Test func 备份列表和还原() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        model.draft.appearance.fontPoint = 26
        await model.apply()
        model.loadBackups()
        #expect(model.backups.count == 2)
        await model.restore(model.backups[0].id)
        #expect(model.notice?.title.hasPrefix("已还原到") == true)
        model.loadBackups()
        #expect(model.backups.count == 3)   // 还原前又备份了一份
    }

    @Test func 诊断() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try InstallFixtures.writeInfoPlist(app: m.locations.squirrelApp, version: "1.1.2")   // Doctor 靠它判断装没装
        let model = try MainModel(env: m.environment())
        await model.runDiagnostics()
        #expect(model.checks.contains { $0.name == "鼠须管" })
        #expect(model.checks.contains { $0.name == "输入法" && $0.level == .ok })
    }

    @Test func 导入时下载失败就用本地旧版本_真的导入了() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        let b = try T.machine(userDB: [:]); defer { b.dir.remove() }
        try SettingsStore(paths: b.paths).save(Settings(schemas: ["py"]))
        var env = b.environment()
        env.fetchPackage = { _ in throw HTTPError.transport("断网了") }
        let model = try MainModel(env: env)
        await model.importFile(file)
        #expect(model.saved == T.settings)
        #expect(model.notice?.action == nil)
        #expect(model.notice?.lines.contains { $0.contains("没下载成") } == true)
    }

    @Test func 还原后应用里的同步记录跟着清掉_没应用的改动留着() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.draft.textReplacement.sync = true
        await model.apply()
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.saved.textReplacement.syncedEntries != nil)
        model.draft.appearance.fontPoint = 30   // 还没应用的改动
        model.loadBackups()
        await model.restore(model.backups[0].id)
        let onDisk = try #require(try SettingsStore(paths: m.paths).load())
        #expect(model.saved == onDisk)
        #expect(model.saved.textReplacement.syncedEntries == nil)
        #expect(model.draft.textReplacement.syncedEntries == nil)
        #expect(model.draft.appearance.fontPoint == 30)
        #expect(model.notice?.lines.contains { $0.contains("rimectl") } == false)
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus?.changes == nil)   // 和诊断一致：还没同步过
    }

    @Test func 同步文本替换只同步_别的改动留在草稿里() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let a = Phrase(text: "替换甲", code: "tha", weight: 1)
        let b = Phrase(text: "替换乙", code: "thb", weight: 1)
        let r = Replacements([a])
        let model = try MainModel(env: m.environment(textReplacements: { r.get() }))
        model.draft.textReplacement.sync = true
        await model.apply()
        let font = model.saved.appearance.fontPoint
        r.set([a, b])
        model.draft.appearance.fontPoint = 30   // 还没应用的改动
        await model.syncTextReplacement()
        #expect(model.saved.appearance.fontPoint == font)
        #expect(try SettingsStore(paths: m.paths).load()?.appearance.fontPoint == font)
        #expect(model.draft.appearance.fontPoint == 30)
        #expect(model.isDirty)
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus?.changes == TextReplacementSync.Changes(added: 0, removed: 0))
    }

    @Test func 应用时新下载了包_配色列表跟着更新() async throws {
        // 本地缓存里原来没有：应用时才下载下来
        let m = try T.machine(); defer { m.dir.remove() }
        final class Fetched: @unchecked Sendable {
            let lock = NSLock()
            var ids: Set<String> = []
            func add(_ id: String) { lock.withLock { _ = ids.insert(id) } }
            func has(_ id: String) -> Bool { lock.withLock { ids.contains(id) } }
        }
        let fetched = Fetched()
        var env = m.environment()
        let fetch = env.fetchPackage
        let cached = env.cachedPackage
        env.fetchPackage = { spec in fetched.add(spec.id); return try await fetch(spec) }
        env.cachedPackage = { spec in fetched.has(spec.id) ? cached(spec) : nil }
        let model = try MainModel(env: env)
        #expect(model.colorSchemes.isEmpty)
        await model.apply()
        #expect(!model.colorSchemes.isEmpty)
    }

    @Test func 同步开着读不了文本替换时_说可以先关同步() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        struct Unreadable: Error, CustomStringConvertible { var description: String { "没有权限" } }
        let model = try MainModel(env: m.environment(textReplacements: { throw Unreadable() }))
        model.draft.textReplacement.sync = true
        await model.apply()
        #expect(model.notice?.title == "读不了 macOS 文本替换，没有写入")
        #expect(model.notice?.lines.contains { $0.contains("关掉同步") } == true)
    }

    @Test func 只有目录在Rime外面的改动时_不问覆盖_直接说不能写() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try SettingsStore(paths: m.paths).save(Settings(schemas: ["wb"]))   // 五笔要写 cn/a.dict.yaml
        let fm = FileManager.default
        try fm.createDirectory(at: m.locations.rimeDirectory, withIntermediateDirectories: true)
        let outside = m.dir.url.appending(path: "dotfiles/cn", directoryHint: .isDirectory)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: m.locations.rimeDirectory.appending(path: "cn"), withDestinationURL: outside)
        let model = try MainModel(env: m.environment())
        await model.apply()
        #expect(model.pendingExternalChanges == nil)
        #expect(model.notice?.title == "这些文件不能写，没有写入")
    }

    @Test func 关掉外部改动弹窗等于放弃() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        try Data("# 外面改的\n".utf8).write(to: m.locations.rimeDirectory.appending(path: "squirrel.custom.yaml"))
        model.draft.appearance.fontPoint = 30
        await model.apply()
        #expect(model.pendingExternalChanges != nil)
        model.dismissExternalChanges()
        #expect(model.pendingExternalChanges == nil)
        #expect(model.isDirty)   // 草稿还在
    }

    @Test func 导入后读不了设置时_说导入好了但要重开() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        try Data("坏了".utf8).write(to: m.paths.settingsFile)
        let note = try #require(model.reloadSettingsAfterImport())
        #expect(note.contains("导入好了"))
        #expect(note.contains("退出应用再打开"))
    }

    @Test func 没通知到鼠须管时不说等了很久() async throws {
        // 终审：通知失败时根本没等，也不会自己部署；提示要说清楚怎么办
        let m = try T.machine(); defer { m.dir.remove() }
        m.squirrel.reloadError = .commandFailed("reload", "测试")
        m.squirrel.launchError = .commandFailed("open", "测试")
        let model = try MainModel(env: m.environment())
        await model.apply()
        let lines = try #require(model.notice?.lines)
        #expect(lines.contains { $0.contains("没通知到鼠须管") })
        #expect(!lines.contains { $0.contains("等了很久") })
    }
}
