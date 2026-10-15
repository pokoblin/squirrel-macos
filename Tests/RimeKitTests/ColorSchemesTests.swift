import Foundation
import Testing
@testable import RimeKit

@Suite struct ColorSchemesTests {
    @Test func 从包里读出配色() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url)
        // 拼音包的 squirrel.yaml 有 aqua（碧水）；五笔包自带的 squirrel.custom.yaml 补丁里有 roseo（玫枫）、roseo_dark（玫枫暗）
        let schemes = try ColorSchemes.available(in: [packages["pinyin"]!, packages["wubi"]!, packages["words"]!])
        #expect(schemes == [
            ColorSchemeInfo(id: "aqua", name: "碧水"),
            ColorSchemeInfo(id: "roseo", name: "玫枫"),
            ColorSchemeInfo(id: "roseo_dark", name: "玫枫暗"),
        ])
    }

    @Test func 没有配色的包是空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url)
        #expect(try ColorSchemes.available(in: [packages["words"]!]) == [])
    }
}
