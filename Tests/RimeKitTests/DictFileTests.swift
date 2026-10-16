import Foundation
import Testing
@testable import RimeKit

@Suite struct DictFileTests {
    static let sample =
        "# 注释\n---\nname: x\nversion: \"1\"\nsort: original\ndict_grouped: true\n...\n## 分组一\n张三丰\txddh\n\n奇怪 的行\n李四\tsbl\t20\tsb\n"

    @Test func 往返不变() throws {
        #expect(try DictFile.parse(Self.sample).render() == Self.sample)
    }

    @Test func 往返不变含BOM和Windows换行和无结尾换行() throws {
        for text in [
            "\u{FEFF}" + Self.sample,
            Self.sample.replacingOccurrences(of: "\n", with: "\r\n"),
            String(Self.sample.dropLast()),
        ] {
            #expect(try DictFile.parse(text).render() == text)
        }
    }

    @Test func 读出词条() throws {
        let f = try DictFile.parse(Self.sample)
        #expect(
            f.entries == [
                DictEntry(text: "张三丰", code: "xddh", weight: nil),
                DictEntry(text: "李四", code: "sbl", weight: 20),
            ])
        #expect(f.columns == ["text", "code", "weight"])
    }

    @Test func 只写词的行() throws {
        let f = try DictFile.parse("---\nname: x\n...\n王五\n")
        #expect(f.entries == [DictEntry(text: "王五", code: nil, weight: nil)])
    }

    @Test func 权重读不出来就原样保留() throws {
        let text = "---\nname: x\n...\n词\tabc\t50%\n好\tabd\t3\n"
        let f = try DictFile.parse(text)
        #expect(f.entries == [DictEntry(text: "好", code: "abd", weight: 3)])
        #expect(f.render() == text)
    }

    @Test func 列顺序按头部() throws {
        let text = "---\nname: x\ncolumns:\n  - text\n  - weight\n  - code\n...\n词\t5\tabc\n"
        var f = try DictFile.parse(text)
        #expect(f.entries == [DictEntry(text: "词", code: "abc", weight: 5)])
        f.append(DictEntry(text: "新", code: "xyz", weight: 7))
        f.append(DictEntry(text: "无权", code: "q", weight: nil))
        #expect(f.render() == text + "新\t7\txyz\n无权\t\tq\n")
    }

    @Test func 默认列写新词() throws {
        var f = try DictFile.parse("---\nname: x\n...\n")
        f.append(DictEntry(text: "甲", code: "a", weight: 1))
        f.append(DictEntry(text: "乙", code: "b", weight: nil))
        f.append(DictEntry(text: "丙", code: nil, weight: nil))
        #expect(f.render() == "---\nname: x\n...\n甲\ta\t1\n乙\tb\n丙\n")
    }

    @Test func 加词改词删词只动对应的行() throws {
        var f = try DictFile.parse(Self.sample)
        // 改第二个词条：只有那一行变，stem 列留着
        f.replaceEntry(at: 1, with: DictEntry(text: "李四", code: "sbl", weight: 30))
        #expect(f.render() == Self.sample.replacingOccurrences(of: "李四\tsbl\t20\tsb", with: "李四\tsbl\t30\tsb"))
        // 加词
        f.append(DictEntry(text: "赵六", code: "abc", weight: nil))
        #expect(f.render().hasSuffix("李四\tsbl\t30\tsb\n赵六\tabc\n"))
        // 删词
        f.removeEntries { $0.text == "张三丰" }
        #expect(
            f.render()
                == "# 注释\n---\nname: x\nversion: \"1\"\nsort: original\ndict_grouped: true\n...\n## 分组一\n\n奇怪 的行\n李四\tsbl\t30\tsb\n赵六\tabc\n"
        )
    }

    @Test func 内容没变的替换保留原行() throws {
        var f = try DictFile.parse(Self.sample)
        f.replaceEntry(at: 1, with: DictEntry(text: "李四", code: "sbl", weight: 20))
        #expect(f.render() == Self.sample)
    }

    @Test func 末尾没有换行时加词先补换行() throws {
        var f = try DictFile.parse("---\nname: x\n...\n甲\ta")
        f.append(DictEntry(text: "乙", code: "b", weight: nil))
        #expect(f.render() == "---\nname: x\n...\n甲\ta\n乙\tb\n")
    }

    @Test func 读头部() throws {
        let text =
            "---\nname: x\nsort: by_weight\nimport_tables:\n  - a_user  # 个人\n  - a_extra # 扩展\n...\n"
        let f = try DictFile.parse(text)
        #expect(f.importTables == ["a_user", "a_extra"])
        #expect(f.sort == "by_weight")
        #expect(f.render() == text)
    }

    @Test func 没有头部() {
        #expect(throws: DictFileError.noHeader) { try DictFile.parse("张三\tabc\n") }
        #expect(throws: DictFileError.noHeader) { try DictFile.parse("---\nname: x\n张三\tabc\n") }
    }

    @Test func 不是UTF8() {
        #expect(throws: DictFileError.notUTF8) { try DictFile.parse(data: Data([0xFF, 0xFE, 0x00, 0xD8])) }
    }

    @Test func 改词时额外的列和缺的列() throws {
        // 只有 text 的行加上编码；有 stem 的行去掉权重，stem 还在
        var f = try DictFile.parse("---\nname: x\n...\n王五\n李四\tsbl\t20\tsb\n")
        f.replaceEntry(at: 0, with: DictEntry(text: "王五", code: "gd", weight: 3))
        f.replaceEntry(at: 1, with: DictEntry(text: "李四", code: "sbl", weight: nil))
        #expect(f.render() == "---\nname: x\n...\n王五\tgd\t3\n李四\tsbl\t\tsb\n")
    }

    static let mixed = "---\r\nname: x\n...\n甲\ta\r\n乙\tb\n# 注\r\n丙\tc\r\n"

    @Test func 混合换行往返不变() throws {
        #expect(try DictFile.parse(Self.mixed).render() == Self.mixed)
    }

    @Test func 混合换行文件改一行只动那一行() throws {
        var f = try DictFile.parse(Self.mixed)
        #expect(f.entries.count == 3)
        f.replaceEntry(at: 1, with: DictEntry(text: "乙", code: "b", weight: 9))
        #expect(f.render() == "---\r\nname: x\n...\n甲\ta\r\n乙\tb\t9\n# 注\r\n丙\tc\r\n")
        f.replaceEntry(at: 0, with: DictEntry(text: "甲", code: "a", weight: 1))
        #expect(f.render() == "---\r\nname: x\n...\n甲\ta\t1\r\n乙\tb\t9\n# 注\r\n丙\tc\r\n")
        f.removeEntries { $0.text == "丙" }
        f.append(DictEntry(text: "丁", code: "d", weight: nil))
        // CRLF 行多，新行用 CRLF
        #expect(f.render() == "---\r\nname: x\n...\n甲\ta\t1\r\n乙\tb\t9\n# 注\r\n丁\td\r\n")
    }

    @Test func 从Data读保留BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(Self.sample.utf8))
        let f = try DictFile.parse(data: data)
        #expect(Data(f.render().utf8) == data)
        #expect(f.entries.count == 2)
        let plain = Data(Self.sample.utf8)
        #expect(Data(try DictFile.parse(data: plain).render().utf8) == plain)
    }
}
