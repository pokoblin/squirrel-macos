import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverSurveyTests {
    func write(_ text: String, _ path: String, in dir: URL) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func 目录不存在或者只有Rime自己的文件算空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        #expect(try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog()).isEmpty)
        try write("var: {}\n", "user.yaml", in: rime)
        try write("installation_id: x\n", "installation.yaml", in: rime)
        try write("x", "build/py.prism.bin", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey == TakeoverSurvey(isEmpty: true, schemas: [], unknownSchemas: [], packages: []))
    }

    @Test func 方案列表从default补丁里读_认不出的单独列出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  schema_list:\n    - schema: wb_py\n    - schema: luna_pinyin\n    - schema: wb\n    - schema: wb\n", "default.custom.yaml", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey == TakeoverSurvey(isEmpty: false, schemas: ["wb_py", "wb"], unknownSchemas: ["luna_pinyin"], packages: ["wubi"]))
    }

    @Test func 补丁里没有方案列表时看default_yaml() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  menu/page_size: 7\n", "default.custom.yaml", in: rime)
        try write("schema_list:\n  - schema: sp\n  - schema: py\nmenu:\n  page_size: 5\n", "default.yaml", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey.schemas == ["sp", "py"])
        #expect(survey.packages == ["pinyin"])
    }

    @Test func 有配置但认不出方案() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("随手记\n", "notes.txt", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey == TakeoverSurvey(isEmpty: false, schemas: [], unknownSchemas: [], packages: []))
    }

    @Test func 补丁写坏了会说是哪个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  schema_list: [\n", "default.custom.yaml", in: rime)
        do {
            _ = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
            Issue.record("应该报错")
        } catch let TakeoverError.badYAML(file, _) {
            #expect(file == "default.custom.yaml")
        }
    }

    @Test func 读词库头里的import_tables() {
        let text = "# 注释\n---\nname: py_ext\nimport_tables:\n  - py_user\n  - cn/a\n...\n你好\tni hao\t1\n"
        #expect(TakeoverFiles.importTables(text) == ["py_user", "cn/a"])
        #expect(TakeoverFiles.importTables("---\nname: x\n...\n") == [])
    }

    @Test func 只追加方案时接在default_yaml的列表后面() throws {
        // 终审：只写 schema_list/+（Rime 文档里常见的写法）时，追加的方案不能丢
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  schema_list/+:\n    - schema: sp\n", "default.custom.yaml", in: rime)
        try write("schema_list:\n  - schema: py\n", "default.yaml", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey.schemas == ["py", "sp"])
    }
}
