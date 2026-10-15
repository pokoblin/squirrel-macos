import Foundation
import Testing
@testable import RimeKit

@Suite struct PackageOptionTests {
    static let json = """
    {"formatVersion":1,"packages":[
     {"id":"dicts","name":"词库","summary":"s","license":"MIT","homepage":"https://example.com/d",
      "source":{"type":"githubReleaseAsset","repo":"o/d","tag":"t","asset":"d.zip"},
      "anchor":"cn/a.dict.yaml","include":["cn/*"],"exclude":[],"requiredFiles":["cn/a.dict.yaml"],
      "schemas":[],"dependencies":[]},
     {"id":"wubi","name":"五笔","summary":"s","license":"MIT","homepage":"https://example.com/w",
      "source":{"type":"githubBranch","repo":"o/w","branch":"main"},
      "anchor":"wb.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["wb.schema.yaml"],
      "schemas":[{"id":"wb","name":"五笔","category":"wubi"},{"id":"wpy","name":"拼音","category":"pinyin"}],
      "dependencies":[],
      "options":[{"id":"pinyinDictionary","name":"拼音词库","defaultChoice":"ext","choices":[
        {"id":"builtin","name":"自带","dependencies":[],"generatedDicts":[],"patches":{}},
        {"id":"ext","name":"大词库","dependencies":["dicts"],
         "generatedDicts":[{"name":"py_ext","importTables":[{"name":"py_user","onlyIfPersonal":true},{"name":"cn/a"}]}],
         "patches":{"wpy":{"translator/dictionary":"py_ext"},"wb":{"reverse_lookup/dictionary":"py_ext"}}}
      ]}]}
    ]}
    """

    static func data(replacing old: String, with new: String) -> Data {
        precondition(json.components(separatedBy: old).count == 2, "要替换的文字必须正好出现一次：\(old)")
        return Data(json.replacingOccurrences(of: old, with: new).utf8)
    }

    @Test func 能读出选项() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        let wubi = try #require(catalog.package("wubi"))
        let option = try #require(wubi.options.first)
        #expect(option.id == "pinyinDictionary")
        #expect(option.defaultChoice == "ext")
        let ext = try #require(option.choice("ext"))
        #expect(ext.dependencies == ["dicts"])
        #expect(ext.generatedDicts.first?.importTables == [ImportTable(name: "py_user", onlyIfPersonal: true), ImportTable(name: "cn/a", onlyIfPersonal: false)])
        #expect(ext.patches["wb"] == ["reverse_lookup/dictionary": "py_ext"])
        #expect(option.choice("nope") == nil)
    }

    @Test func 没写选项的包选项为空() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        #expect(catalog.package("dicts")?.options == [])
    }

    @Test func 默认选择不存在() {
        #expect(throws: CatalogError.unknownDefaultChoice(package: "wubi", option: "pinyinDictionary")) {
            try Catalog.decode(Self.data(replacing: #""defaultChoice":"ext""#, with: #""defaultChoice":"zzz""#))
        }
    }

    @Test func 选项依赖了不存在的包() {
        #expect(throws: CatalogError.unknownDependency(package: "wubi", dependency: "nope")) {
            try Catalog.decode(Self.data(replacing: #""dependencies":["dicts"]"#, with: #""dependencies":["nope"]"#))
        }
    }

    @Test func 选项补丁写给了别的包的方案() {
        #expect(throws: CatalogError.patchForUnknownSchema(package: "wubi", schema: "other")) {
            try Catalog.decode(Self.data(replacing: #""wpy":{"translator/dictionary":"py_ext"}"#, with: #""other":{"translator/dictionary":"py_ext"}"#))
        }
    }

    @Test func 按方案找所属的包() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        #expect(catalog.packageOwning(schema: "wpy")?.id == "wubi")
        #expect(catalog.packageOwning(schema: "nope") == nil)
    }

    @Test func 编码再解码不变() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        #expect(try Catalog.decode(try JSONCoding.encoder.encode(catalog)) == catalog)
    }
}
