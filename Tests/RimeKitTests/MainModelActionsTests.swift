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
}
