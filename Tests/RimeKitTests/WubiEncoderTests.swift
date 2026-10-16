import Foundation
import Testing
@testable import RimeKit

@Suite struct WubiEncoderTests {
    func enc() throws -> WubiEncoder {
        try WubiEncoder(mainDict: DictFile.parse(WubiFixtures.mainDict))
    }

    @Test func 三字词() throws { #expect(try enc().encode("张三丰") == .codes(["xddh"])) }

    @Test func 二字词() throws { #expect(try enc().encode("张三") == .codes(["xtdg"])) }

    @Test func 二字词取首二码() throws {
        // 夹具里「你 wqiy 20 / 仰泳 10」：仰 wq + 泳 iy
        #expect(try enc().encode("仰泳") == .codes(["wqiy"]))
    }

    @Test func 四字词() throws {
        // AaBaCaZa：张首码 x、三首码 d、丰首码 d、五首码 g
        #expect(try enc().encode("张三丰五") == .codes(["xddg"]))
    }

    @Test func 十字词() throws {
        #expect(try enc().encode(String(repeating: "张", count: 10)) == .codes(["xxxx"]))
    }

    @Test func 超出规则的长度() throws {
        // 十一个字：规则只到十
        #expect(try enc().encode(String(repeating: "张", count: 11)) == .unknown([]))
    }

    @Test func 最长码不止一个时列出组合() throws {
        // 戈有两个四码全码 afny、ghny；二字词取第一字首二码：戈在前
        #expect(try enc().encode("戈张") == .codes(["afxt", "ghxt"]))
        // 戈在后：四字词取最后一字首码
        #expect(try enc().encode("张三丰戈") == .codes(["xdda", "xddg"]))
    }

    @Test func 组合顺序按出现先后() throws {
        // 两个字都有两个全码时，前一字的在外层
        let dict = try DictFile.parse(
            "---\nencoder:\n  rules:\n    - length_equal: 2\n      formula: \"AaAbBaBb\"\n...\n甲\tabcd\n甲\tefcd\n乙\tghij\n乙\tklij\n")
        #expect(try WubiEncoder(mainDict: dict).encode("甲乙") == .codes(["abgh", "abkl", "efgh", "efkl"]))
    }

    @Test func 排除z开头的码() throws {
        // 泳 的最长码 ziyiy 以 z 开头，不算，全码是 iyiy
        #expect(try enc().encode("泳张") == .codes(["iyxt"]))
        #expect(try enc().encode("张三泳") == .codes(["xdiy"]))  // AaBaCaCb：泳第二码 y
    }

    @Test func 主词库里没有的字() throws {
        #expect(try enc().encode("张\u{20000}") == .unknown(["\u{20000}"]))  // 扩展区汉字
        #expect(try enc().encode("张A") == .unknown(["A"]))
        #expect(try enc().encode("张😀") == .unknown(["😀"]))
        #expect(try enc().encode("张1") == .unknown(["1"]))
    }

    @Test func 没有的字列全不重复() throws {
        #expect(try enc().encode("A张B张A") == .unknown(["A", "B"]))
    }

    @Test func 单字() throws { #expect(try enc().encode("张") == .singleCharacter) }

    @Test func 单字不在词库里也是单字() throws {
        #expect(try enc().encode("A") == .singleCharacter)
    }

    @Test func 空串() throws { #expect(try enc().encode("") == .unknown([])) }

    @Test(arguments: ["a", "abcd", "xddh", "y"]) func 合法编码(_ c: String) {
        #expect(WubiEncoder.isValidCode(c))
    }

    @Test(arguments: ["", "abcde", "z", "abz", "AB", "a1", "ab cd", "ａｂ"]) func 不合法编码(_ c: String) {
        #expect(!WubiEncoder.isValidCode(c))
    }

    @Test func 没有规则() throws {
        let noEncoder = try DictFile.parse("---\nname: x\n...\n张\txt\n")
        #expect(throws: WubiEncoderError.noRules) { try WubiEncoder(mainDict: noEncoder) }
        let emptyRules = try DictFile.parse("---\nencoder:\n  rules: []\n...\n")
        #expect(throws: WubiEncoderError.noRules) { try WubiEncoder(mainDict: emptyRules) }
    }

    @Test func 能识别夹具里的全部规则() throws {
        // 夹具的 encoder 段和真包一样：二字词、三字词、四到十字词
        #expect(try enc().encode("张三") == .codes(["xtdg"]))
        #expect(try enc().encode("张三丰") == .codes(["xddh"]))
    }

    @Test func 夹具编译() throws {
        guard RimeTools.installed else { return }
        let dir = try TempDir()
        defer { dir.remove() }
        let out = try WubiFixtures.compiled(in: dir.url.appending(path: "rime"))
        #expect(FileManager.default.fileExists(atPath: out.appending(path: "build/wubi86_jidian.schema.yaml").path))
    }

    @Test func 夹具包写成缓存格式() throws {
        let dir = try TempDir()
        defer { dir.remove() }
        let pkg = try WubiFixtures.makePackage(in: dir.url)
        #expect(pkg.info.id == "wubi86-jidian")
        let main = try Data(contentsOf: pkg.filesDirectory.appending(path: WubiFixtures.mainName))
        #expect(try DictFile.parse(data: main).entries.contains { $0.text == "仰泳" })
    }
}
