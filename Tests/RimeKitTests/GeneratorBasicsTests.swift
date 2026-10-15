import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorBasicsTests {
    let builtinDict = ["wubi": ["pinyinDictionary": "builtin"]]

    @Test func 复制上游文件但不复制上游补丁和许可证() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "py"], options: builtinDict), packages: packages), into: out)

        #expect(GenFixtures.exists(out, "py.schema.yaml"))
        #expect(GenFixtures.exists(out, "wb.dict.yaml"))
        #expect(!GenFixtures.exists(out, "LICENSE"))
        #expect(!GenFixtures.exists(out, "cn/a.dict.yaml"))   // 选了自带词库，不需要 words
        #expect(result.files.contains(GeneratedFile(path: "wb.dict.yaml", origin: .package("wubi"))))
        #expect(result.files.contains(GeneratedFile(path: "default.custom.yaml", origin: .generated)))
        #expect(result.files.map(\.path) == result.files.map(\.path).sorted())
        #expect(result.warnings.isEmpty)
    }

    @Test func 方案列表按设置的顺序并保留上游的其它补丁() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        var settings = Settings(schemas: ["py", "wb"], options: builtinDict)
        settings.appearance.pageSize = 7
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)

        let p = try GenFixtures.patch(out, "default")
        #expect(p.entries.map(\.key) == ["menu", "key_binder", "schema_list", "menu/page_size"])
        #expect(p["schema_list"]?.sequence?.compactMap { $0["schema"]?.string } == ["py", "wb"])
        #expect(p["menu/page_size"]?.string == "7")
        #expect(p["key_binder"]?["bindings"]?.sequence?.count == 1)
        #expect(try GenFixtures.read(out, "default.custom.yaml").hasPrefix(Patch.header))
    }

    @Test func 保留的补丁在上游之后应用管理的键之前() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        var settings = Settings(schemas: ["wb"], options: builtinDict)
        settings.preservedPatches = ["default": [
            PreservedPatch(key: "key_binder/bindings/@next", yaml: "{when: has_menu, accept: minus, send: Page_Up}"),
            PreservedPatch(key: "schema_list", yaml: "[{schema: old}]"),
        ]]
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)

        let p = try GenFixtures.patch(out, "default")
        #expect(p.entries.map(\.key) == ["menu", "key_binder", "key_binder/bindings/@next", "schema_list"])
        #expect(p["key_binder/bindings/@next"]?["accept"]?.string == "minus")
        #expect(p["schema_list"]?.sequence?.compactMap { $0["schema"]?.string } == ["wb"])   // 应用管理的键覆盖保留的
    }

    @Test func 输出目录不是空的就拒绝() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: out.appending(path: "old.txt"))
        #expect(throws: GenerationError.outputNotEmpty(out.path)) {
            try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages), into: out)
        }
    }

    @Test func 缺包就报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        packages["words"] = nil
        #expect(throws: GenerationError.missingPackage("words")) {
            try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages),
                                           into: dir.url.appending(path: "out"))
        }
    }

    @Test func 两个包有同一个文件而且内容不同时提醒() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"),
                                                    extra: ["pinyin": ["shared.yaml": "a: 1\n"], "wubi": ["shared.yaml": "a: 2\n"]])
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["py", "wb"], options: builtinDict), packages: packages), into: out)
        #expect(try GenFixtures.read(out, "shared.yaml") == "a: 2\n")   // 安装顺序里后面的包覆盖前面的
        #expect(result.warnings == ["shared.yaml 在好几个包里都有而且内容不一样，用的是 wubi 的"])
        #expect(result.files.contains(GeneratedFile(path: "shared.yaml", origin: .package("wubi"))))
    }

    @Test func 上游补丁写坏了报出是哪个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"),
                                                    extra: ["wubi": ["default.custom.yaml": "patch:\n  a: [1, 2\n"]])
        let error = #expect(throws: GenerationError.self) {
            try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"], options: builtinDict), packages: packages),
                                           into: dir.url.appending(path: "out"))
        }
        guard case .badYAML(let file, _) = error else {
            Issue.record("应该是 badYAML，实际是 \(String(describing: error))")
            return
        }
        #expect(file == "wubi/default.custom.yaml")
    }
}
