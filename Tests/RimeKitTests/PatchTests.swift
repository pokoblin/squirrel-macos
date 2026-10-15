import Foundation
import Testing
import Yams
@testable import RimeKit

@Suite struct PatchTests {
    @Test func 同一个键再写一次会移到最后() {
        var p = Patch()
        p.set("a", YAMLNode.text("1"))
        p.set("b", YAMLNode.text("2"))
        p.set("a", YAMLNode.text("3"))
        #expect(p.entries.map(\.key) == ["b", "a"])
        #expect(p["a"]?.string == "3")
    }

    @Test func 合并时后面的覆盖前面的() {
        var base = Patch()
        base.set("menu/page_size", YAMLNode.int(5))
        base.set("x", YAMLNode.text("keep"))
        var other = Patch()
        other.set("menu/page_size", YAMLNode.int(7))
        base.merge(other)
        #expect(base.entries.map(\.key) == ["x", "menu/page_size"])
        #expect(base["menu/page_size"]?.string == "7")
    }

    @Test func 读上游的补丁文件保留顺序和嵌套() throws {
        let text = """
        # 注释
        patch:
          style:
            color_scheme: roseo_maple   # 行尾注释
          preset_color_schemes:
            roseo_maple:
              font_point: 18
          "menu/page_size": 5
        """
        let p = try Patch.parse(customYAML: text)
        #expect(p.entries.map(\.key) == ["style", "preset_color_schemes", "menu/page_size"])
        #expect(p["style"]?["color_scheme"]?.string == "roseo_maple")
        #expect(p["preset_color_schemes"]?["roseo_maple"]?["font_point"]?.string == "18")
    }

    @Test func 没有patch段或空文件得到空补丁() throws {
        #expect(try Patch.parse(customYAML: "").isEmpty)
        #expect(try Patch.parse(customYAML: "# 只有注释\n").isEmpty)
        #expect(try Patch.parse(customYAML: "other: 1\n").isEmpty)
    }

    @Test func 写出来再读回去不变() throws {
        var p = Patch()
        p.set("schema_list", YAMLNode.list([YAMLNode.map([("schema", YAMLNode.text("wubi86_jidian_pinyin"))])]))
        p.set("preset_color_schemes/roseo_maple/font_point", YAMLNode.int(24))
        p.set("custom_phrase", YAMLNode.map([("dictionary", YAMLNode.text("")), ("enable_sentence", YAMLNode.bool(false))]))
        p.set("name", YAMLNode.text("玫枫"))
        let text = try p.renderCustomYAML()
        #expect(text.hasPrefix(Patch.header))
        #expect(text.contains("玫枫"))   // 中文不转义
        let back = try Patch.parse(customYAML: text)
        #expect(back.entries.map(\.key) == p.entries.map(\.key))
        #expect(back["schema_list"]?.sequence?.first?["schema"]?.string == "wubi86_jidian_pinyin")
        #expect(back["preset_color_schemes/roseo_maple/font_point"]?.string == "24")
        #expect(back["custom_phrase"]?["dictionary"]?.string == "")
        #expect(back["custom_phrase"]?["enable_sentence"]?.string == "false")
    }

    @Test func 空字符串写成引号而不是空值() throws {
        var p = Patch()
        p.set("custom_phrase", YAMLNode.map([("dictionary", YAMLNode.text(""))]))
        let text = try p.renderCustomYAML()
        #expect(text.contains("dictionary: \"\"") || text.contains("dictionary: ''"), "\(text)")
    }

    @Test func 坏的YAML会报错() {
        #expect(throws: (any Error).self) {
            try Patch.parse(customYAML: "patch:\n  a: [1, 2\n")
        }
    }
}
