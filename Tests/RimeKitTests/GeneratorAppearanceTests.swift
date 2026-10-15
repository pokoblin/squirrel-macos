import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorAppearanceTests {
    func generate(_ settings: Settings, _ dir: TempDir) throws -> URL {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)
        return out
    }

    @Test func 字号同时写到style和上游补丁里的浅色深色配色() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["wb"])
        s.appearance.fontPoint = 24
        s.appearance.labelFontPoint = 20
        s.appearance.candidateListLayout = .linear
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")

        #expect(p["style/font_point"]?.string == "24")
        #expect(p["preset_color_schemes/roseo/font_point"]?.string == "24")
        #expect(p["preset_color_schemes/roseo_dark/font_point"]?.string == "24")
        #expect(p["preset_color_schemes/roseo/label_font_point"]?.string == "20")
        #expect(p["style/candidate_list_layout"]?.string == "linear")
        #expect(p["preset_color_schemes/roseo_dark/candidate_list_layout"]?.string == "linear")
        // 上游整体替换配色的那条在前，我们改字号的在后，Rime 按顺序应用，所以字号生效
        let keys = p.entries.map(\.key)
        #expect(keys.firstIndex(of: "preset_color_schemes")! < keys.firstIndex(of: "preset_color_schemes/roseo/font_point")!)
    }

    @Test func 没有上游补丁时用包里squirrel_yaml的配色() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["py"])
        s.appearance.fontPoint = 20
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")
        #expect(p["preset_color_schemes/aqua/font_point"]?.string == "20")
        #expect(p.entries.map(\.key) == ["style/font_point", "preset_color_schemes/aqua/font_point"])
    }

    @Test func 设置里指定的配色优先() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["wb"])
        s.appearance.colorScheme = "luna"
        s.appearance.commentFontPoint = 14
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")
        #expect(p["style/color_scheme"]?.string == "luna")
        #expect(p["preset_color_schemes/luna/comment_font_point"]?.string == "14")
        #expect(p["preset_color_schemes/roseo_dark/comment_font_point"]?.string == "14")
        #expect(p["preset_color_schemes/roseo/comment_font_point"] == nil)
    }

    @Test func 竖排() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["py"])
        s.appearance.textOrientation = .vertical
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")
        #expect(p["style/text_orientation"]?.string == "vertical")
        #expect(p["preset_color_schemes/aqua/text_orientation"]?.string == "vertical")
    }

    @Test func 什么都没设也没有上游补丁时不生成文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try generate(Settings(schemas: ["py"]), dir)
        #expect(!GenFixtures.exists(out, "squirrel.custom.yaml"))
    }

    @Test func 没设外观时上游补丁原样保留() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try GenFixtures.patch(try generate(Settings(schemas: ["wb"]), dir), "squirrel")
        #expect(p.entries.map(\.key) == ["style", "preset_color_schemes"])
    }
}
