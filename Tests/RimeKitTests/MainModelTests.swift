import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct MainModelTests {
    typealias T = TransferFixtures

    @Test func 打开时读出设置_没有改动() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment(), welcome: ["设置好了"])
        #expect(model.saved == T.settings)
        #expect(model.draft == T.settings)
        #expect(!model.isDirty)
        #expect(model.notice?.lines == ["设置好了"])
    }

    @Test func 没有设置时打不开() throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        #expect(throws: TransferError.noSettings) { try MainModel(env: m.environment()) }
    }

    @Test func 启用和关掉方案_至少留一个() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)
        #expect(model.draft.schemas == ["wb_py", "py", "wb"])
        #expect(model.isDirty)
        model.setEnabled("wb_py", false)
        model.setEnabled("py", false)
        #expect(model.draft.schemas == ["wb"])
        model.setEnabled("wb", false)
        #expect(model.draft.schemas == ["wb"])
        #expect(model.notice?.title == "至少要留一个方案")
    }

    @Test func 调整顺序_第一个是默认方案() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)                       // [wb_py, py, wb]
        model.moveSchemas(from: IndexSet(integer: 2), to: 0)
        #expect(model.draft.schemas == ["wb", "wb_py", "py"])
        model.moveSchemas(from: IndexSet(integer: 0), to: 3)
        #expect(model.draft.schemas == ["wb_py", "py", "wb"])
    }

    @Test func 撤销() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)
        model.draft.appearance.fontPoint = 30
        model.revert()
        #expect(model.draft == model.saved)
        #expect(!model.isDirty)
    }

    @Test func 包选项() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(model.optionPackages.map(\.id) == ["wubi"])
        let wubi = model.optionPackages[0]
        let option = wubi.options[0]
        #expect(model.choice(option, of: wubi) == "ext")
        model.setChoice("builtin", option: option, of: wubi)
        #expect(model.draft.options["wubi"]?["pinyinDictionary"] == "builtin")
    }

    @Test func 方案名字和配色列表() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(model.schemaName("wb_py") == "五笔拼音")
        #expect(model.schemaName("nope") == "nope")
        #expect(model.colorSchemes.map(\.id) == ["aqua", "roseo", "roseo_dark"])
        #expect(model.catalogPackages.map(\.id) == ["pinyin", "wubi"])   // 没有方案的词库包不列
    }

    @Test func 同时启用好几个方案包时提醒() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(model.mixedPackagesNote != nil)             // wb_py 和 py 来自两个包
        model.setEnabled("py", false)
        #expect(model.mixedPackagesNote == nil)
    }

    @Test func 选项改回默认值不算有改动() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try SettingsStore(paths: m.paths).save(Settings(schemas: ["wb_py", "py"]))   // 没有写选项：都是默认值
        let model = try MainModel(env: m.environment())
        let wubi = model.optionPackages[0]
        let option = wubi.options[0]
        let other = try #require(option.choices.first { $0.id != option.defaultChoice })
        model.setChoice(other.id, option: option, of: wubi)
        #expect(model.isDirty)
        model.setChoice(option.defaultChoice, option: option, of: wubi)
        #expect(!model.isDirty)
    }
}
