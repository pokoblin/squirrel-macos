import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogTests {
    @Test func 能读出清单的各个字段() throws {
        let catalog = try Fixtures.catalog()
        #expect(catalog.formatVersion == 1)
        #expect(catalog.packages.map(\.id) == ["base", "app"])
        let base = try #require(catalog.package("base"))
        #expect(base.source == .githubReleaseAsset(repo: "o/base", tag: "t", asset: "base.zip"))
        #expect(base.include == [FileGlob("*.schema.yaml"), FileGlob("dicts/**")])
        #expect(base.schemas == [SchemaSpec(id: "base", name: "基础", category: .pinyin)])
        let app = try #require(catalog.package("app"))
        #expect(app.source == .githubBranch(repo: "o/app", branch: "main"))
        #expect(app.dependencies == ["base"])
        #expect(catalog.package("nope") == nil)
    }

    @Test func 编码再解码不变() throws {
        let catalog = try Fixtures.catalog()
        let data = try JSONCoding.encoder.encode(catalog)
        #expect(try Catalog.decode(data) == catalog)
    }

    @Test func 不认识的格式版本() {
        #expect(throws: CatalogError.unsupportedFormat(2)) {
            try Catalog.decode(Fixtures.catalogData(replacing: #""formatVersion":1"#, with: #""formatVersion":2"#))
        }
    }

    @Test func 包名重复() {
        #expect(throws: CatalogError.duplicatePackageID("base")) {
            try Catalog.decode(Fixtures.catalogData(
                replacing: #"{"id":"app","name":"应用","summary""#,
                with: #"{"id":"base","name":"应用","summary""#))
        }
    }

    @Test func 方案名重复() {
        #expect(throws: CatalogError.duplicateSchemaID("base")) {
            try Catalog.decode(Fixtures.catalogData(
                replacing: #"[{"id":"app","name":"应用","category":"wubi"}]"#,
                with: #"[{"id":"base","name":"应用","category":"wubi"}]"#))
        }
    }

    @Test func 依赖了不存在的包() {
        #expect(throws: CatalogError.unknownDependency(package: "app", dependency: "nope")) {
            try Catalog.decode(Fixtures.catalogData(replacing: #""dependencies":["base"]"#, with: #""dependencies":["nope"]"#))
        }
    }

    @Test func 循环依赖() {
        let error = #expect(throws: CatalogError.self) {
            try Catalog.decode(Fixtures.catalogData(replacing: #""dependencies":[]}"#, with: #""dependencies":["app"]}"#))
        }
        guard case .dependencyCycle(let path) = error else {
            Issue.record("应该是循环依赖，实际是 \(String(describing: error))")
            return
        }
        #expect(path.first == path.last)
        #expect(Set(path) == ["base", "app"])
    }

    @Test func 必需文件不在安装规则里() {
        #expect(throws: CatalogError.requiredFileNotIncluded(package: "app", file: "lib/x.lua")) {
            try Catalog.decode(Fixtures.catalogData(
                replacing: #""requiredFiles":["app.schema.yaml"]"#,
                with: #""requiredFiles":["app.schema.yaml","lib/x.lua"]"#))
        }
    }

    @Test func 个人词库模板要在包根目录而且在安装规则里() {
        let notIncluded = Fixtures.catalogData(
            replacing: #""requiredFiles":["app.schema.yaml"],"#,
            with: #""requiredFiles":["app.schema.yaml"],"userDicts":["app_user.dict.yaml"],"#)
        #expect(throws: CatalogError.badUserDict(package: "app", file: "app_user.dict.yaml")) {
            try Catalog.decode(notIncluded)
        }
        let inSubdirectory = Fixtures.catalogData(
            replacing: #""requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"],"#,
            with: #""requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"],"userDicts":["dicts/a.dict.yaml"],"#)
        #expect(throws: CatalogError.badUserDict(package: "base", file: "dicts/a.dict.yaml")) {
            try Catalog.decode(inSubdirectory)
        }
    }

    @Test func 没写个人词库模板时是空的() throws {
        #expect(try Fixtures.catalog().package("app")?.userDicts == [])
    }

    @Test func 安装顺序依赖在前而且不重复() throws {
        let catalog = try Fixtures.catalog()
        #expect(try catalog.installOrder(for: ["app"]).map(\.id) == ["base", "app"])
        #expect(try catalog.installOrder(for: ["app", "base"]).map(\.id) == ["base", "app"])
        #expect(try catalog.installOrder(for: ["base"]).map(\.id) == ["base"])
    }

    @Test func 安装顺序遇到不存在的包() throws {
        let catalog = try Fixtures.catalog()
        #expect(throws: CatalogError.unknownPackage("nope")) {
            try catalog.installOrder(for: ["nope"])
        }
    }

    @Test func 错误信息是中文() {
        #expect(CatalogError.unknownPackage("x").description == "清单里没有这个包：x")
    }
}
