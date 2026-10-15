import Foundation
import Testing
@testable import RimeKit

@Suite struct FileGlobTests {
    @Test func 星号只匹配同一层() {
        let g = FileGlob("*.schema.yaml")
        #expect(g.matches("rime_ice.schema.yaml"))
        #expect(!g.matches("sub/rime_ice.schema.yaml"))
        #expect(!g.matches("rime_ice.dict.yaml"))
    }

    @Test func 带目录的星号() {
        let g = FileGlob("cn_dicts/*.dict.yaml")
        #expect(g.matches("cn_dicts/8105.dict.yaml"))
        #expect(!g.matches("cn_dicts/deep/8105.dict.yaml"))
        #expect(!g.matches("8105.dict.yaml"))
    }

    @Test func 两个星号匹配任意深度() {
        let g = FileGlob("lua/**")
        #expect(g.matches("lua/date_translator.lua"))
        #expect(g.matches("lua/cold_word_drop/filter.lua"))
        #expect(!g.matches("lua"))
        #expect(!g.matches("lua2/x.lua"))
        #expect(!g.matches("other/lua/x.lua"))
    }

    @Test func 精确文件名() {
        let g = FileGlob("default.yaml")
        #expect(g.matches("default.yaml"))
        #expect(!g.matches("x/default.yaml"))
    }

    @Test func JSON里是字符串() throws {
        let data = Data(#"["*.yaml","lua/**"]"#.utf8)
        let globs = try JSONDecoder().decode([FileGlob].self, from: data)
        #expect(globs == [FileGlob("*.yaml"), FileGlob("lua/**")])
        let back = try JSONEncoder().encode(globs)
        #expect(String(decoding: back, as: UTF8.self) == #"["*.yaml","lua\/**"]"#)
    }
}
