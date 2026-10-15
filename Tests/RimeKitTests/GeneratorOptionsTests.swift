import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorOptionsTests {
    func personal(_ dir: TempDir, _ dicts: [String: String]) throws -> PersonalContent {
        let base = dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, text) in dicts.sorted(by: { $0.key < $1.key }) {
            let url = base.appending(path: name)
            try Data(text.utf8).write(to: url)
            urls.append(url)
        }
        return PersonalContent(dicts: urls, phrases: [])
    }

    @Test func 默认选大词库时生成总词库和补丁() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "wpy"]), packages: packages), into: out)

        #expect(GenFixtures.exists(out, "cn/a.dict.yaml"))   // 选项依赖的 words 包
        let dict = try GenFixtures.read(out, "py_ext.dict.yaml")
        #expect(dict.contains("name: py_ext"))
        #expect(dict.contains("  - cn/a\n"))
        #expect(!dict.contains("py_user"))   // 没有个人词库就不挂
        #expect(result.files.contains(GeneratedFile(path: "py_ext.dict.yaml", origin: .generated)))
        #expect(try GenFixtures.patch(out, "wb")["reverse_lookup/dictionary"]?.string == "py_ext")
        #expect(try GenFixtures.patch(out, "wpy")["translator/dictionary"]?.string == "py_ext")
        // wb_py 没启用也写补丁：启用的方案可能通过 schema/dependencies 用到它
        #expect(try GenFixtures.patch(out, "wb_py")["reverse_lookup/dictionary"]?.string == "py_ext")
    }

    @Test func 有个人词库时挂到总词库最前面() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let mine = try personal(dir, ["py_user.dict.yaml": GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"])])
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wpy"]), packages: packages, personal: mine), into: out)
        let dict = try GenFixtures.read(out, "py_ext.dict.yaml")
        #expect(dict.contains("import_tables:\n  - py_user\n  - cn/a\n"))
        #expect(result.files.contains(GeneratedFile(path: "py_user.dict.yaml", origin: .personal)))
    }

    @Test func 个人词库和上游模板同名时用个人的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let mine = try personal(dir, ["wb_user.dict.yaml": GenFixtures.dict("wb_user", ["我的词\tqrrs\t1"])])
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages, personal: mine), into: out)
        #expect(try GenFixtures.read(out, "wb_user.dict.yaml").contains("我的词"))
        #expect(result.files.contains(GeneratedFile(path: "wb_user.dict.yaml", origin: .personal)))
    }

    @Test func 选自带词库时什么都不加() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "wpy"], options: ["wubi": ["pinyinDictionary": "builtin"]]),
                                  packages: packages), into: out)
        #expect(!GenFixtures.exists(out, "py_ext.dict.yaml"))
        #expect(!GenFixtures.exists(out, "wb.custom.yaml"))
        #expect(!GenFixtures.exists(out, "cn/a.dict.yaml"))
    }
}
