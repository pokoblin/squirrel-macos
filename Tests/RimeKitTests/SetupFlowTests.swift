import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct SetupFlowTests {
    typealias T = TransferFixtures
    typealias F = TakeoverFixtures

    static let ready = InputSourceState(registered: true, enabled: true, selected: true)

    func phrases(_ list: [Phrase]) -> @Sendable () throws -> TextReplacementSnapshot {
        { TextReplacementSnapshot(usable: list, badShortcut: 0, badPhrase: 0) }
    }

    @Test func 已经设置好的不再引导() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(m.paths)
        let flow = SetupFlow(env: m.environment())
        await flow.start()
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
    }

    @Test func 没装鼠须管时先装() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try FileManager.default.removeItem(at: m.locations.squirrelApp)
        let app = m.locations.squirrelApp
        let flow = SetupFlow(env: m.environment(input: FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false)),
                                                install: {
            // 模拟装好：放一个可执行的 rime_deployer
            let deployer = app.appending(path: "Contents/MacOS/rime_deployer")
            try FileManager.default.createDirectory(at: deployer.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: deployer)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deployer.path)
            return .installed("1.1.2", previous: nil)
        }))
        await flow.start()
        #expect(flow.step == .needInstall)
        await flow.install()
        #expect(flow.step == .needInputMethod(nil))
    }

    @Test func 取消授权时说清楚() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try FileManager.default.removeItem(at: m.locations.squirrelApp)
        let flow = SetupFlow(env: m.environment(install: { throw InstallError.cancelled }))
        await flow.start()
        await flow.install()
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("取消"))
    }

    @Test func 添加输入法后看Rime目录_空的就选起步方案() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        input.enableAfterPumps = 2
        let flow = SetupFlow(env: m.environment(input: input))
        await flow.start()
        #expect(flow.step == .needInputMethod(nil))
        await flow.addInputMethod()
        #expect(flow.step == .chooseStart(.empty))
        #expect(input.calls.contains("open"))
    }

    @Test func 已经添加但没选中时切换过去() async throws {
        // 测试机实测：设置好了但输入法还是英文，因为没切换过去（设计 6.2：好了自动切换过去）
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: false))
        let flow = SetupFlow(env: m.environment(input: input))
        await flow.start()
        #expect(flow.step == .chooseStart(.empty))
        #expect(input.calls.contains("select"))
        #expect(input.state().selected)
    }

    @Test func 等添加输入法超时() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let flow = SetupFlow(env: m.environment(input: FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))))
        await flow.addInputMethod()
        guard case .needInputMethod(let note) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(note?.contains("还没看到") == true)
    }

    @Test func 选起步方案后写好配置() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let flow = SetupFlow(env: m.environment())
        await flow.start()
        #expect(flow.step == .chooseStart(.empty))
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(try SettingsStore(paths: m.paths).load()?.schemas == ["py"])
        #expect(!(try Ledger.load(m.paths).entries.isEmpty))
        #expect(FileManager.default.fileExists(atPath: m.locations.rimeDirectory.appending(path: "py.schema.yaml").path))
    }

    @Test func 编译失败时说清楚_什么都不保存() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        let flow = SetupFlow(env: m.environment(compiler: failing))
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("编译不过"))
        #expect(!FileManager.default.fileExists(atPath: m.paths.settingsFile.path))
    }

    @Test func 有已有配置时先预览_点了才接管() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.wubiSample(m.packages, into: m.locations.rimeDirectory)
        let flow = SetupFlow(env: m.environment(textReplacements: phrases([F.fromTR])))
        await flow.start()
        guard case .chooseStart(.existing(let summary)) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(summary.schemas == ["五笔拼音（wb_py）", "五笔（wb）"])
        #expect(summary.canConfirm)
        #expect(!FileManager.default.fileExists(atPath: m.paths.settingsFile.path))   // 预览不写任何东西
        await flow.confirmTakeover()
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(try SettingsStore(paths: m.paths).load()?.schemas == ["wb_py", "wb"])
    }

    @Test func 读不了文本替换时不能接管() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.wubiSample(m.packages, into: m.locations.rimeDirectory)
        struct Unreadable: Error, CustomStringConvertible { var description: String { "数据库打不开" } }
        let flow = SetupFlow(env: m.environment(textReplacements: { throw Unreadable() }))
        await flow.start()
        guard case .chooseStart(.existing(let summary)) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(!summary.canConfirm)
        #expect(summary.blockedReason?.contains("数据库打不开") == true)
        await flow.confirmTakeover()
        #expect(!FileManager.default.fileExists(atPath: m.paths.settingsFile.path))
    }

    @Test func 认不出方案时让用户选起步方案() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.put("随手记\n", "notes.txt", in: m.locations.rimeDirectory)
        let flow = SetupFlow(env: m.environment())
        await flow.start()
        #expect(flow.step == .chooseStart(.unrecognized))
    }

    @Test func 从导出文件导入() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let flow = SetupFlow(env: b.environment())
        await flow.start()
        await flow.importFile(file)
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        #expect(b.tool.dbs["wb_py"] == T.snapshot)
    }

    @Test func 不是导出文件时说清楚() async throws {
        let b = try T.machine(withSettings: false); defer { b.dir.remove() }
        let file = b.dir.url.appending(path: "x.zip")
        try Data("不是".utf8).write(to: file)
        let flow = SetupFlow(env: b.environment())
        await flow.importFile(file)
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("不是 squirrel-macos 的导出文件"))
    }
}
