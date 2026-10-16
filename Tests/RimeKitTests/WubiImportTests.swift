import Foundation
import Testing
@testable import RimeKit

/// 批量导入：解析文本，给每一行算编码和状态
@Suite struct WubiImportTests {
    func encoder() throws -> WubiEncoder {
        try WubiEncoder(mainDict: DictFile.parse(WubiFixtures.mainDict))
    }

    func parse(_ text: String, user: [String] = ["分组词条\twxyt"]) throws -> [ImportRow] {
        WubiImport.parse(text, encoder: try encoder(), index: try WubiCodeIndexTests.index(user: user))
    }

    // MARK: 三种格式

    @Test func 只写词自动算编码() throws {
        let rows = try parse("张三丰")
        #expect(rows == [ImportRow(id: 1, text: "张三丰", code: "xddh", choices: ["xddh"], weight: nil, status: .ok, selected: true)])
    }

    @Test func 词加编码() throws {
        let rows = try parse("张三丰 xddh")
        #expect(rows.count == 1)
        #expect(rows[0].text == "张三丰")
        #expect(rows[0].code == "xddh")
        #expect(rows[0].weight == nil)
        #expect(rows[0].status == .ok)
        // 给的编码和算出来的不一样，就用给的
        let other = try parse("张三丰 abcd")
        #expect(other[0].code == "abcd")
        #expect(other[0].status == .ok)
    }

    @Test func 词加编码加权重() throws {
        let rows = try parse("李四\tsbl\t20")
        #expect(rows[0].text == "李四")
        #expect(rows[0].code == "sbl")
        #expect(rows[0].weight == 20)
        #expect(rows[0].status == .ok)
        #expect(rows[0].selected)
    }

    @Test func 给了编码的词不管算不算得出来都可以加() throws {
        // 「李」主词库里没有，算不出；有合法编码就可以
        let rows = try parse("李四 sbl")
        #expect(rows[0].status == .ok)
        // 单字给了编码也行
        let single = try parse("泉 ewhj")
        #expect(single[0].status == .ok)
        #expect(single[0].code == "ewhj")
    }

    @Test func 词里有空格只能用Tab() throws {
        let rows = try parse("New York\tnyyk")
        #expect(rows[0].text == "New York")
        #expect(rows[0].code == "nyyk")
        #expect(rows[0].status == .ok)
    }

    @Test func 没有Tab时按空格拆() throws {
        let rows = try parse("New York nyyk")
        #expect(rows[0].text == "New")
        #expect(rows[0].code == "York")   // 不合法
        #expect(rows[0].status == .needsCode)
        #expect(!rows[0].selected)

        let three = try parse("张三丰   xddh   30")
        #expect(three[0].text == "张三丰")
        #expect(three[0].code == "xddh")
        #expect(three[0].weight == 30)
        #expect(three[0].status == .ok)
    }

    @Test func 空格拆出多余的段标需要编码() throws {
        let rows = try parse("张三丰 xddh 30 多余")
        #expect(rows[0].status == .needsCode)
        #expect(!rows[0].selected)
    }

    @Test func 权重不是整数标需要编码() throws {
        let rows = try parse("张三丰\txddh\t很多")
        #expect(rows[0].status == .needsCode)
        #expect(rows[0].weight == nil)
        #expect(!rows[0].selected)
    }

    @Test func Tab拆出的第四列是词库的stem直接忽略() throws {
        let rows = try parse("张三丰\txddh\t30\txddh")
        #expect(rows[0].code == "xddh")
        #expect(rows[0].weight == 30)
        #expect(rows[0].status == .ok)
    }

    // MARK: 状态

    @Test func 编码不合法() throws {
        for bad in ["abcde", "ABCD", "ab1", "zabc", "ab-c"] {
            let rows = try parse("张三 \(bad)")
            #expect(rows[0].status == .needsCode, "\(bad)")
            #expect(rows[0].code == bad)
            #expect(!rows[0].selected)
        }
    }

    @Test func 算不出() throws {
        let rows = try parse("张😀")
        #expect(rows[0].status == .needsCode)
        #expect(rows[0].code == "")
        #expect(rows[0].choices.isEmpty)
        #expect(!rows[0].selected)
    }

    @Test func 单字没给编码要填() throws {
        let rows = try parse("张")
        #expect(rows[0].status == .needsCode)
        #expect(rows[0].code == "")
        #expect(!rows[0].selected)
    }

    @Test func 多个可能的编码() throws {
        // 戈 有两个一样长的全码：afny、ghny
        let rows = try parse("张戈")
        #expect(rows[0].status == .choose)
        #expect(rows[0].code == "xtaf")
        #expect(rows[0].choices == ["xtaf", "xtgh"])
        #expect(rows[0].selected)
    }

    @Test func 已经加过() throws {
        let rows = try parse("分组词条 wxyt")
        #expect(rows[0].status == .alreadyPersonal)
        #expect(!rows[0].selected)
    }

    @Test func 词库里已经有() throws {
        // 主词库里有 仰泳 wqiy
        let rows = try parse("仰泳")
        #expect(rows[0].status == .alreadyInDict)
        #expect(rows[0].code == "wqiy")
        #expect(!rows[0].selected)
    }

    @Test func 这次导入里重复只留第一行() throws {
        let rows = try parse("张三丰\n李四 sbl\n张三丰 xddh\n李四 sbl\n李四 sbl")
        #expect(rows.map(\.status) == [.ok, .ok, .duplicateInBatch, .duplicateInBatch, .duplicateInBatch])
        #expect(rows.map(\.selected) == [true, true, false, false, false])
    }

    @Test func 同一个词不同编码不算重复() throws {
        let rows = try parse("李四 sbl\n李四 sbla")
        #expect(rows.map(\.status) == [.ok, .ok])
    }

    @Test func 算不出编码的重复行按词比() throws {
        let rows = try parse("张😀\n张😀")
        #expect(rows.map(\.status) == [.needsCode, .duplicateInBatch])
    }

    @Test func 重复比已经加过优先() throws {
        let rows = try parse("分组词条 wxyt\n分组词条 wxyt")
        #expect(rows.map(\.status) == [.alreadyPersonal, .duplicateInBatch])
    }

    // MARK: 文本的各种样子（Review Focus 3）

    @Test func 开头有BOM() throws {
        let rows = try parse("\u{FEFF}张三丰\n李四 sbl")
        #expect(rows.map(\.text) == ["张三丰", "李四"])
        #expect(rows[0].code == "xddh")
    }

    @Test func Windows换行() throws {
        let rows = try parse("张三丰\r\n李四\tsbl\t20\r\n\r\n王五 wgd\r\n")
        #expect(rows.map(\.text) == ["张三丰", "李四", "王五"])
        #expect(rows[1].weight == 20)
        #expect(rows[2].code == "wgd")
        #expect(rows.map(\.id) == [1, 2, 4])
    }

    @Test func 旧Mac换行() throws {
        let rows = try parse("张三丰\r李四 sbl")
        #expect(rows.map(\.text) == ["张三丰", "李四"])
    }

    @Test func 行尾空白() throws {
        let rows = try parse("张三丰   \n李四\tsbl\t20  \t \n王五 wgd\u{3000}")
        #expect(rows.map(\.text) == ["张三丰", "李四", "王五"])
        #expect(rows[1].weight == 20)
        #expect(rows[2].code == "wgd")
        #expect(rows.allSatisfy { $0.status == .ok })
    }

    @Test func 全角空格当分隔符() throws {
        let rows = try parse("李四\u{3000}sbl\u{3000}20")
        #expect(rows[0].text == "李四")
        #expect(rows[0].code == "sbl")
        #expect(rows[0].weight == 20)
        #expect(rows[0].status == .ok)
        // 全角和半角混着用
        let mixed = try parse("李四\u{3000} sbl \u{3000}20")
        #expect(mixed[0].code == "sbl")
        #expect(mixed[0].weight == 20)
    }

    @Test func 空行和注释行跳过() throws {
        let rows = try parse("# 注释\n\n   \n张三丰\n  # 缩进的注释\n#李四 sbl\n李四 sbl")
        #expect(rows.map(\.text) == ["张三丰", "李四"])
        #expect(rows.map(\.id) == [4, 7])
    }

    @Test func 头部跳过() throws {
        let text = """
        # Rime dictionary
        ---
        name: my_words
        version: "1"
        sort: original
        columns:
          - text
          - code
        ...
        张三丰
        李四\tsbl\t20
        """
        let rows = try parse(text)
        #expect(rows.map(\.text) == ["张三丰", "李四"])
        #expect(rows.map(\.id) == [10, 11])
        #expect(rows[1].weight == 20)
    }

    @Test func 头部跳过时开头有BOM和Windows换行() throws {
        let rows = try parse("\u{FEFF}---\r\nname: x\r\n...\r\n张三丰\r\n")
        #expect(rows.map(\.text) == ["张三丰"])
    }

    @Test func 只有横线没有三个点不跳头部() throws {
        let rows = try parse("---\n张三丰\n李四 sbl")
        #expect(rows.map(\.text) == ["---", "张三丰", "李四"])
        #expect(rows[0].status == .needsCode)
        #expect(!rows[0].selected)
        #expect(rows[1].status == .ok)
    }

    @Test func 三个点在横线前面不跳头部() throws {
        let rows = try parse("张三丰\n...\n---\n李四 sbl")
        #expect(rows.map(\.text) == ["张三丰", "...", "---", "李四"])
        #expect(rows.map(\.id) == [1, 2, 3, 4])
        #expect(rows[0].status == .ok)
        #expect(rows[1].status == .needsCode)
    }

    @Test func 词表中间的横线不吞掉前面的词() throws {
        let rows = try parse("张三丰\n李四 sbl\n---\n王五 wgd\n...\n赵六 xyz")
        #expect(rows.map(\.text) == ["张三丰", "李四", "---", "王五", "...", "赵六"])
        #expect(rows[0].status == .ok)
        #expect(rows[1].status == .ok)
        #expect(rows[2].status == .needsCode)
        #expect(rows[5].code == "xyz")
    }

    @Test func 头部前面只有注释和空行才算头部() throws {
        let rows = try parse("# 说明\n\n---\nname: x\n...\n张三丰")
        #expect(rows.map(\.text) == ["张三丰"])
        #expect(rows[0].id == 6)
    }

    @Test func 词是空的行留着标需要编码() throws {
        let rows = try parse("\t张三丰\n\tabcd\n  \t\n李四 sbl")
        #expect(rows.map(\.id) == [1, 2, 4])
        #expect(rows[0].text == "")
        #expect(rows.prefix(2).allSatisfy { $0.status == .needsCode && !$0.selected })
        // 勾上也不会生成空词的词条
        var forced = rows
        forced[1].selected = true
        #expect(WubiImport.entries(from: forced) == [DictEntry(text: "李四", code: "sbl", weight: nil)])
    }

    @Test func 空文本没有行() throws {
        #expect(try parse("").isEmpty)
        #expect(try parse("\n\n# 只有注释\n").isEmpty)
    }

    // MARK: entries(from:)

    @Test func 只取选中的且编码合法的行() throws {
        var rows = try parse("张三丰\n李四\tsbl\t20\n张三 abcde\n仰泳\n张😀\n张戈")
        // 张三丰 ok、李四 ok、张三 不合法、仰泳 已有、张😀 算不出、张戈 choose
        #expect(WubiImport.entries(from: rows) == [
            DictEntry(text: "张三丰", code: "xddh", weight: nil),
            DictEntry(text: "李四", code: "sbl", weight: 20),
            DictEntry(text: "张戈", code: "xtaf", weight: nil),
        ])
        // 用户取消勾选
        rows[0].selected = false
        #expect(WubiImport.entries(from: rows).map(\.text) == ["李四", "张戈"])
        // 用户填了编码并勾上
        rows[4].code = "xrty"
        rows[4].selected = true
        #expect(WubiImport.entries(from: rows).map(\.text) == ["李四", "张😀", "张戈"])
        // 勾上了但编码还是不合法的，不取
        rows[2].selected = true
        #expect(WubiImport.entries(from: rows).map(\.text) == ["李四", "张😀", "张戈"])
    }
}
