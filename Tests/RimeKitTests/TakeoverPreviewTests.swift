import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverPreviewTests {
    typealias F = TakeoverFixtures

    func preview(_ e: F.Env, _ p: TakeoverProposal) throws -> TakeoverPreview {
        try TakeoverPreview.make(p, rime: e.rime, catalog: e.catalog, packages: e.packages,
                                 textReplacement: [F.fromTR], staging: e.dir.url.appending(path: "staging", directoryHint: .isDirectory))
    }

    /// 目录里每个文件的哈希
    func snapshot(_ dir: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: dir.path) {
            let url = dir.appending(path: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                result[path] = try Hashing.sha256(of: url)
            }
        }
        return result
    }

    @Test func 应用生成的配置接管后什么都不变() throws {
        let e = try F.env(); defer { e.dir.remove() }
        let personalDir = e.dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try F.put(GenFixtures.dict("py_user", ["私人词条\tsi ren ci tiao\t100"]), "py_user.dict.yaml", in: personalDir)
        try F.put(GenFixtures.dict("wb_user", ["私人五笔词\taaaa"]), "wb_user.dict.yaml", in: personalDir)
        let settings = Settings(
            schemas: ["wb_py", "wb", "py"],
            options: ["wubi": ["pinyinDictionary": "ext"]],
            appearance: Appearance(fontPoint: 24, labelFontPoint: 20, pageSize: 7),
            textReplacement: TextReplacementSettings(sync: true),
            preservedPatches: ["default": [PreservedPatch(key: "key_binder/bindings",
                                                          yaml: "- {when: has_menu, accept: minus, send: Page_Up}\n")]])
        let personal = PersonalContent(dicts: [personalDir.appending(path: "py_user.dict.yaml"), personalDir.appending(path: "wb_user.dict.yaml")],
                                       phrases: [F.manual])
        _ = try ConfigGenerator().generate(
            GenFixtures.input(settings, packages: e.packages, personal: personal, textReplacement: [F.fromTR]), into: e.rime)

        let p = try F.analyze(e)
        #expect(p.settings.schemas == settings.schemas)
        #expect(p.settings.options == settings.options)
        #expect(p.settings.appearance == settings.appearance)
        #expect(p.settings.textReplacement == settings.textReplacement)
        #expect(p.settings.preservedPatches["default"]?.map(\.key) == ["key_binder/bindings"])
        #expect(p.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(p.manualPhrases == [F.manual])
        #expect(p.textReplacementMatches == 1)
        #expect(p.notes.isEmpty, "\(p.notes)")

        let v = try preview(e, p)
        #expect(v.replaced == [], "\(v.replaced)")
        #expect(v.added == [])
        #expect(v.kept == [])
    }

    @Test func 手写样本的预览() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let before = try snapshot(e.rime)
        let v = try preview(e, try F.analyze(e))
        #expect(v.kept == ["notes.txt", "weasel.custom.yaml"])
        #expect(v.replaced.contains("default.custom.yaml"))
        #expect(v.replaced.contains("squirrel.custom.yaml"))
        #expect(v.unchanged.contains("wb.dict.yaml"))
        #expect(v.unchanged.contains("wb_user.dict.yaml"))
        #expect(v.added == [])
        #expect(try snapshot(e.rime) == before)   // 预览不改 Rime 目录
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.dir.url.appending(path: "staging").path).isEmpty)
    }

    @Test func 改过的上游词库和方案文件会提醒() throws {
        // 常见做法：照上游说明在词库的 import_tables 里加自己的词库。接管后换成上游版本，就不再导入了
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        try F.put("---\nname: wb\nversion: \"1\"\nsort: by_weight\nimport_tables:\n  - wb_mine\n...\n一\tg\t100\n", "wb.dict.yaml", in: e.rime)
        try F.put(GenFixtures.dict("wb_mine", ["我的词\tqqqq"]), "wb_mine.dict.yaml", in: e.rime)
        try F.put(F.upstream("wubi", "wb.schema.yaml") + "# 自己改过\n", "wb.schema.yaml", in: e.rime)
        let v = try preview(e, try F.analyze(e))
        #expect(v.kept.contains("wb_mine.dict.yaml"))
        #expect(v.warnings.contains { $0.contains("wb.dict.yaml") && $0.contains("wb_mine") })
        #expect(v.warnings.contains { $0.contains("wb.schema.yaml") })
    }

    @Test func 用户直接改过的上游文件会被换掉() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "wb.dict.yaml") + "自己加的\tzjjd\n", "wb.dict.yaml", in: e.rime)
        #expect(try preview(e, try F.analyze(e)).replaced.contains("wb.dict.yaml"))
    }
}
