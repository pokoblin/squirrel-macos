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
