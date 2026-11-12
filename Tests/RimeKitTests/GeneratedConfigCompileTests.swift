import Foundation
import Testing
@testable import RimeKit

/// 用宿主机上的鼠须管编译生成结果，再模拟打字。没装鼠须管时跳过。
@Suite(.enabled(if: RimeTools.installed))
struct GeneratedConfigCompileTests {
    @Test func 生成的配置能编译而且能打出字() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let personalDir = dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: personalDir, withIntermediateDirectories: true)
        let userDict = personalDir.appending(path: "py_user.dict.yaml")
        try Data(GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"]).utf8).write(to: userDict)
        let personal = PersonalContent(dicts: [userDict], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])

        var settings = Settings(schemas: ["wb", "wpy", "py", "sp"])
        settings.appearance.fontPoint = 24
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages, personal: personal), into: out)

        let build = try RimeTools.build(out)
        #expect(build.status == 0, "\(build.stderr)")
        for file in ["wb.prism.bin", "wb.table.bin", "py_ext.table.bin", "py.table.bin"] {
            #expect(GenFixtures.exists(out, "build/\(file)"), "缺少 build/\(file)")
        }
        let compiledWB = try GenFixtures.read(out, "build/wb.schema.yaml")
        #expect(compiledWB.contains("py_ext"))
        #expect(compiledWB.contains("table_translator@custom_phrase"))

        let wb = try RimeTools.type(out, schema: "wb", ["g", "tstx"])
        #expect(wb["g"]?.first == "一")
        #expect(wb["tstx"]?.first == "测试短语")

        let wpy = try RimeTools.type(out, schema: "wpy", ["daciku", "jingyu"])
        #expect(wpy["daciku"]?.first == "大词库")   // 选项生成的总词库生效
        #expect(wpy["jingyu"]?.first == "鲸鱼")     // 个人词库挂进去了

        let py = try RimeTools.type(out, schema: "py", ["nihao", "tstx", "sy"])
        #expect(py["nihao"]?.first == "你好")
        #expect(py["tstx"]?.first == "测试短语")
        #expect(py["sy"]?.first == "上游短语")      // 上游短语还在

        let sp = try RimeTools.type(out, schema: "sp", ["tstx"])
        #expect(sp["tstx"]?.first == "测试短语")     // 双拼用自己的短语文件也有
    }
}

@Suite(.enabled(if: RimeTools.installed))
struct UniquifierCompileTests {
    @Test func 置顶的短语和词库里的同一个字只出现一次() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let personal = PersonalContent(dicts: [], phrases: [Phrase(text: "一", code: "g", weight: nil)])
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "wpy"]), packages: packages, personal: personal), into: out)
        let build = try RimeTools.build(out)
        #expect(build.status == 0, "\(build.stderr)")
        let wb = try RimeTools.type(out, schema: "wb", ["g"])
        #expect(wb["g"]?.first == "一")
        #expect(wb["g"]?.filter { $0 == "一" }.count == 1, "\(wb)")
    }
}

@Suite(.enabled(if: RimeTools.installed))
struct OptionDependencyCompileTests {
    @Test func 只启用五笔时拼音混输也能用() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        // 只启用 wb；wb 依赖的 wpy 没启用，但 wpy 的词库要改成 py_ext，py_ext 才会被编译
        _ = try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages), into: out)
        let build = try RimeTools.build(out)
        #expect(build.status == 0)
        #expect(GenFixtures.exists(out, "build/py_ext.table.bin"), "没有编译出 py_ext")
        let wb = try RimeTools.type(out, schema: "wb", ["g", "daciku"])
        #expect(wb["g"]?.first == "一")
        #expect(wb["daciku"]?.contains("大词库") == true, "\(wb["daciku"] ?? [])")
    }
}

@Suite(.enabled(if: RimeTools.installed))
struct PinyinLearningCompileTests {
    func make(_ dir: TempDir) throws -> URL {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let personalDir = dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: personalDir, withIntermediateDirectories: true)
        let userDict = personalDir.appending(path: "py_user.dict.yaml")
        try Data(GenFixtures.dict("py_user", ["工\tgong\t1", "鲸\tjing\t10", "京\tjing\t1", "鱼\tyu\t1"]).utf8).write(to: userDict)
        let out = dir.url.appending(path: "out")
        // wpy 要在列表里（或被依赖），py_ext 的 prism 才会被编出来
        var settings = Settings(schemas: ["wb", "wb_py", "wpy"])
        // 夹具方案没导入鼠须管默认的按键绑定；真实的极点五笔有 Control+k → Shift+Delete
        settings.preservedPatches["wb_py"] = [PreservedPatch(
            key: "key_binder/bindings", yaml: "- {accept: \"Control+k\", send: \"Shift+Delete\", when: composing}\n")]
        _ = try ConfigGenerator().generate(
            try GenFixtures.input(settings, packages: packages,
                                  personal: PersonalContent(dicts: [userDict], phrases: [])), into: out)
        let build = try RimeTools.build(out)
        #expect(build.status == 0, "\(build.stderr)")
        return out
    }

    @Test func 混输记词能编译能用() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try make(dir)
        let compiled = try GenFixtures.read(out, "build/wb_py.schema.yaml")
        #expect(compiled.contains("script_translator@mixed_pinyin"))
        #expect(compiled.contains("lua_filter@*code_hint_wb"))

        let wb = try RimeTools.type(out, schema: "wb", ["g", "a"])
        let mixed = try RimeTools.type(out, schema: "wb_py", ["g", "a", "jingyu"])
        #expect(mixed["g"]?.first == wb["g"]?.first)
        #expect(mixed["a"]?.first == wb["a"]?.first)
        #expect(mixed["jingyu"]?.first == "鲸鱼", "\(mixed["jingyu"] ?? [])")   // 自动连词

        let hints = try RimeTools.typeWithComments(out, schema: "wb_py", ["gong", "a"])
        #expect(hints["gong"]?.first { $0.text == "工" }?.comment == "a", "\(hints["gong"] ?? [])")
        #expect(hints["a"]?.first { $0.text == "工" }?.comment == "", "\(hints["a"] ?? [])")
    }

    @Test func 凑出的词会记住_ctrl_k能删() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try make(dir)
        // jingyu 的候选是「鲸鱼 鲸 京」：3 选「京」，再 1 选「鱼」，凑出和自动连词不一样的「京鱼」
        let typed = try RimeTools.type(out, schema: "wb_py", ["jingyu31"])
        #expect(typed["jingyu31"]?.first == "京鱼", "\(typed)")
        // 每次都是新进程：记住的词写进了用户词库
        #expect(try RimeTools.type(out, schema: "wb_py", ["jingyu"])["jingyu"]?.first == "京鱼")
        _ = try RimeTools.type(out, schema: "wb_py", ["jingyu^k"])
        let after = try RimeTools.type(out, schema: "wb_py", ["jingyu"])["jingyu"] ?? []
        #expect(after.first == "鲸鱼", "\(after)")
    }
}
