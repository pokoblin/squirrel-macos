import Foundation
import Testing
import Yams
@testable import RimeKit

@Suite struct PatchLeavesTests {
    func node(_ yaml: String) throws -> Node { try #require(try YAMLNode.parse(yaml)) }

    @Test func 整段写法拆成叶子() throws {
        let leaves = PatchLeaves.flatten("menu", try node("page_size: 5\nalternative_select_keys: \"123\"\n"))
        #expect(leaves.map(\.path) == ["menu/page_size", "menu/alternative_select_keys"])
        #expect(leaves.first?.value.string == "5")
    }

    @Test func 列表和空映射是叶子() throws {
        #expect(PatchLeaves.flatten("key_binder/bindings", try node("- a\n- b\n")).map(\.path) == ["key_binder/bindings"])
        #expect(PatchLeaves.flatten("x", try node("{}")).map(\.path) == ["x"])
    }

    @Test func 键里有斜杠的映射不拆() throws {
        // 标点映射的键就是 "/"：拆开会得到 Rime 认不出的路径，所以整个映射当一个叶子
        let leaves = PatchLeaves.flatten("punctuator/full_shape", try node("\"/\": [\"／\", \"÷\"]\n\",\": \"，\"\n"))
        #expect(leaves.map(\.path) == ["punctuator/full_shape"])
    }

    @Test func 后写的覆盖先写的() throws {
        var p = Patch()
        p.set("menu/page_size", YAMLNode.int(7))
        p.set("menu", try node("page_size: 5\nfoo: 1\n"))   // 整段写入：清掉原来这一段下面的
        p.set("menu/foo", YAMLNode.int(2))
        let leaves = PatchLeaves(p)
        #expect(leaves.paths == ["menu/page_size", "menu/foo"])
        #expect(leaves["menu/page_size"]?.string == "5")
        #expect(leaves["menu/foo"]?.string == "2")
    }

    @Test func 写下层路径时清掉上层原来的值() throws {
        var leaves = PatchLeaves()
        leaves.set("a", YAMLNode.int(1))
        leaves.set("a/b", YAMLNode.int(2))
        #expect(leaves.paths == ["a/b"])
        #expect(leaves["a"] == nil)
    }

    @Test func 比较值时不管引号和键的顺序() throws {
        #expect(YAMLNode.same(try node("\"5\""), try node("5")))
        #expect(YAMLNode.same(try node("a: 1\nb: [x, y]\n"), try node("b:\n  - x\n  - y\na: '1'\n")))
        #expect(!YAMLNode.same(try node("[1, 2]"), try node("[2, 1]")))
        #expect(!YAMLNode.same(try node("a"), try node("b")))
    }

    @Test func 路径有没有上下级关系() {
        #expect(PatchLeaves.overlaps("menu", "menu/page_size"))
        #expect(PatchLeaves.overlaps("menu/page_size", "menu"))
        #expect(PatchLeaves.overlaps("a", "a"))
        #expect(!PatchLeaves.overlaps("menu/page", "menu/page_size"))
    }
}
