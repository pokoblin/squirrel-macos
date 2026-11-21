import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorKeysTests {
    let prefix = "ascii_composer/switch_key/"

    func generate(_ settings: Settings, _ dir: TempDir, extra: [String: [String: String]] = [:]) throws -> (URL, GenerationResult) {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"), extra: extra)
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)
        return (out, result)
    }

    func settings(_ key: AsciiSwitchKey?, schemas: [String] = ["wb"]) -> Settings {
        Settings(schemas: schemas, keys: KeySettings(asciiSwitchKey: key))
    }

    func values(_ p: Patch) -> [String?] {
        AsciiSwitchKey.keys.map { p[prefix + $0]?.string }
    }

    @Test func 没选时不写ascii_composer() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try GenFixtures.patch(try generate(settings(nil), dir).0, "default")
        #expect(!p.entries.contains { $0.key.hasPrefix("ascii_composer") })
    }

    @Test func 只用左Control() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try GenFixtures.patch(try generate(settings(.leftControl), dir).0, "default")
        #expect(values(p) == ["noop", "noop", "commit_code", "noop"])
    }

    @Test func 沿用上游的切换动作_排在上游整段之后() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let upstream = """
        patch:
          schema_list:
            - schema: wb
          ascii_composer:
            good_old_caps_lock: true
            switch_key:
              Caps_Lock: commit_code
              Shift_L: inline_ascii
              Shift_R: commit_text

        """
        let (out, _) = try generate(settings(.bothShift), dir, extra: ["wubi": ["default.custom.yaml": upstream]])
        let p = try GenFixtures.patch(out, "default")
        #expect(values(p) == ["inline_ascii", "commit_text", "noop", "noop"])
        let keys = p.entries.map(\.key)
        #expect(keys.firstIndex(of: "ascii_composer")! < keys.firstIndex(of: prefix + "Shift_L")!)
        // Caps Lock 不碰
        #expect(p[prefix + "Caps_Lock"] == nil)
    }

    @Test func 包里default_yaml的动作也沿用() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let defaultYAML = "ascii_composer:\n  switch_key:\n    Shift_L: noop\n    Shift_R: commit_text\n"
        let (out, _) = try generate(settings(.bothShift, schemas: ["py"]), dir, extra: ["pinyin": ["default.yaml": defaultYAML]])
        let p = try GenFixtures.patch(out, "default")
        // 原来是 noop 的改成切换时用 commit_code
        #expect(values(p) == ["commit_code", "commit_text", "noop", "noop"])
    }

    @Test func 设置盖过保留补丁() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = settings(AsciiSwitchKey.none)
        s.preservedPatches = ["default": [PreservedPatch(key: prefix + "Shift_L", yaml: "commit_code\n")]]
        let p = try GenFixtures.patch(try generate(s, dir).0, "default")
        #expect(values(p) == ["noop", "noop", "noop", "noop"])
        #expect(p.entries.filter { $0.key == prefix + "Shift_L" }.count == 1)
    }

    @Test func 方案自己定义了切换键时警告() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let schema = GenFixtures.wubiSchema(id: "wb") + "ascii_composer:\n  switch_key:\n    Shift_L: commit_code\n"
        let (_, result) = try generate(settings(.leftControl), dir, extra: ["wubi": ["wb.schema.yaml": schema]])
        #expect(result.warnings.contains { $0.contains("wb") && $0.contains("切换中英文") })
        // 没选时不警告
        let dir2 = try TempDir(); defer { dir2.remove() }
        let (_, quiet) = try generate(settings(nil), dir2, extra: ["wubi": ["wb.schema.yaml": schema]])
        #expect(!quiet.warnings.contains { $0.contains("切换中英文") })
    }
}
