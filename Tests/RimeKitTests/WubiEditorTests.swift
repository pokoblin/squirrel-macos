import Foundation
import Testing
@testable import RimeKit

@Suite struct WubiEditorTests {
    /// 夹具包 + 给定的个人词库内容
    private func editor(_ user: String = WubiFixtures.userDict, in dir: TempDir) throws -> WubiEditor {
        let package = try WubiFixtures.makePackage(in: dir.url.appending(path: "cache", directoryHint: .isDirectory))
        return try WubiEditor(package: package, userFile: DictFile.parse(user))
    }

    // MARK: resolveCode

    @Test func 自动编码和手填编码() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(in: dir)
        #expect(e.resolveCode(text: "仰泳", given: nil) == .success(["wqiy"]))
        #expect(e.resolveCode(text: "甲乙", given: "ab") == .success(["ab"]))
        // 戈有两个一样长的全码，组合起来有好几个
        let many = try e.resolveCode(text: "戈戈", given: nil).get()
        #expect(many.count == 4)
    }

    @Test func 算不出的各种原因() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(in: dir)
        #expect(e.resolveCode(text: "丁丁", given: nil) == .failure(.cannotEncode(["丁"])))
        #expect(e.resolveCode(text: "张", given: nil) == .failure(.singleCharacterNeedsCode))
        #expect(e.resolveCode(text: "甲乙", given: "ABC") == .failure(.invalidCode))
        #expect(e.resolveCode(text: "甲乙", given: "abcde") == .failure(.invalidCode))
        #expect(e.resolveCode(text: "", given: "ab") == .failure(.invalidText))
        #expect(e.resolveCode(text: "甲\t乙", given: "ab") == .failure(.invalidText))
        #expect(e.resolveCode(text: "甲\n乙", given: nil) == .failure(.invalidText))
        #expect(e.resolveCode(text: "甲\r\n乙", given: nil) == .failure(.invalidText))
        // 以 # 开头的写进词库是注释行，加了也打不出来
        #expect(e.resolveCode(text: "#甲乙", given: "ab") == .failure(.invalidText))
        #expect(e.plan(text: "#甲乙", code: "ab", position: nil) == .failure(.invalidText))
        #expect(WubiEditProblem.invalidText.description.contains("#"))
        #expect(e.plan(text: "甲#乙", code: "ab", position: nil) == .success(DictEntry(text: "甲#乙", code: "ab")))
    }

    // MARK: plan

    @Test func 查重() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(WubiFixtures.userDict + "\n甲乙\twqiy\n张三丰\n", in: dir)
        #expect(e.plan(text: "甲乙", code: "wqiy", position: nil) == .failure(.alreadyPersonal))
        #expect(e.plan(text: "仰泳", code: "wqiy", position: nil) == .failure(.alreadyInDict))
        // 没写编码的词条按自动编码算
        #expect(e.plan(text: "张三丰", code: "xddh", position: nil) == .failure(.alreadyPersonal))
        #expect(e.plan(text: "张三丰", code: "xddj", position: nil) == .success(DictEntry(text: "张三丰", code: "xddj")))
    }

    @Test func 词和编码要合法() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(in: dir)
        #expect(e.plan(text: "甲\t乙", code: "ab", position: nil) == .failure(.invalidText))
        #expect(e.plan(text: "甲乙", code: "zz", position: nil) == .failure(.invalidCode))
        #expect(e.plan(text: "甲乙", code: "ab", position: 0) == .failure(.invalidPosition))
    }

    @Test func 位置和权重() throws {
        let dir = try TempDir(); defer { dir.remove() }
        // wqiy 下：你(20)、甲乙(11)、仰泳(10)
        let e = try editor(WubiFixtures.userDict + "\n甲乙\twqiy\t11\n", in: dir)
        #expect(e.plan(text: "丙丁", code: "wqiy", position: 1) == .success(DictEntry(text: "丙丁", code: "wqiy", weight: 30)))
        #expect(e.plan(text: "丙丁", code: "wqiy", position: 2) == .success(DictEntry(text: "丙丁", code: "wqiy", weight: 15)))
        #expect(e.plan(text: "丙丁", code: "wqiy", position: 3) == .failure(.noRoom))
        #expect(e.plan(text: "丙丁", code: "wqiy", position: 4) == .success(DictEntry(text: "丙丁", code: "wqiy")))
        #expect(e.plan(text: "丙丁", code: "wqiy", position: nil) == .success(DictEntry(text: "丙丁", code: "wqiy")))
    }

    // MARK: applying / position

    @Test func 加了以后问排第几() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(in: dir)
        let entry = try e.plan(text: "甲乙", code: "wqiy", position: 1).get()
        let after = e.applying([entry])
        #expect(after.position(of: entry) == 1)
        #expect(after.userFile.entries.last == entry)
        // 原来的编辑器不变
        #expect(e.userFile.entries.count == 1)
        #expect(after.plan(text: "甲乙", code: "wqiy", position: nil) == .failure(.alreadyPersonal))
        let last = try after.plan(text: "丙丁", code: "wqiy", position: nil).get()
        #expect(after.applying([last]).position(of: last) == 4)
    }

    // MARK: 删

    @Test func 找要删的词条() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(WubiFixtures.userDict + "\n甲乙\twqiy\n张三丰\n甲乙\tabcd\n", in: dir)
        // 序号：0 分组词条、1 甲乙 wqiy、2 张三丰（自动）、3 甲乙 abcd
        #expect(e.removeMatches(text: "甲乙", code: nil) == [1, 3])
        #expect(e.removeMatches(text: "甲乙", code: "abcd") == [3])
        #expect(e.removeMatches(text: "张三丰", code: "xddh") == [2])
        #expect(e.removeMatches(text: "张三丰", code: "abcd").isEmpty)
        #expect(e.removeMatches(text: "不存在", code: nil).isEmpty)
        let removed = WubiEditor.remove(indices: [1, 2], from: e.userFile)
        #expect(removed.entries.map(\.text) == ["分组词条", "甲乙"])
        #expect(removed.render().contains("## 示例"))
    }

    // MARK: 检查用的输入

    @Test func 检查时没写编码的补上自动编码() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(WubiFixtures.userDict + "\n张三丰\n丁丁\n", in: dir)
        #expect(e.entriesWithCodes.map(\.code) == ["wxyt", "xddh", nil])
        // 索引里也有补了编码的词，预期位置才算得出来
        #expect(e.index.words(for: "xddh").map(\.text) == ["张三丰"])
        // 文件本身没动
        #expect(e.userFile.entries[1].code == nil)
    }

    // MARK: 导入

    @Test func 导入按自动编码查重() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(WubiFixtures.userDict + "\n张三丰\n", in: dir)
        let rows = e.parseImport("张三丰\n张三丰\txddh\n仰泳\n")
        #expect(rows.map(\.status) == [.alreadyPersonal, .duplicateInBatch, .alreadyInDict])
    }

    // MARK: 改

    @Test func 改编码和位置_查重不算自己() throws {
        let dir = try TempDir(); defer { dir.remove() }
        // 0 分组词条、1 甲乙 wqiy 15、2 张三丰（自动 xddh）、3 甲乙 abcd
        let e = try editor(WubiFixtures.userDict + "\n甲乙\twqiy\t15\n张三丰\n甲乙\tabcd\n", in: dir)
        // 原地不动：编码、位置都没变，权重也不变
        #expect(e.planUpdate(at: 1, code: "wqiy", position: 2) == .success(DictEntry(text: "甲乙", code: "wqiy", weight: 15)))
        // 放第一个：不算自己，你 20 + 10
        #expect(e.planUpdate(at: 1, code: "wqiy", position: 1) == .success(DictEntry(text: "甲乙", code: "wqiy", weight: 30)))
        // 放最后：不写权重
        #expect(e.planUpdate(at: 1, code: "wqiy", position: nil) == .success(DictEntry(text: "甲乙", code: "wqiy")))
        // 没写编码的词改位置：写上编码
        #expect(e.planUpdate(at: 2, code: "xddh", position: nil) == .success(DictEntry(text: "张三丰", code: "xddh")))
        // 和个人词库里另一条重复、和主词库重复、编码不对、序号不对
        #expect(e.planUpdate(at: 3, code: "wqiy", position: nil) == .failure(.alreadyPersonal))
        #expect(e.planUpdate(at: 1, code: "gghg", position: nil) == .success(DictEntry(text: "甲乙", code: "gghg")))
        #expect(e.planUpdate(at: 1, code: "ABC", position: nil) == .failure(.invalidCode))
        #expect(e.planUpdate(at: 9, code: "wqiy", position: nil) == .failure(.noSuchEntry))
        let dup = try editor(WubiFixtures.userDict + "\n仰泳\tabcd\n", in: dir)
        #expect(dup.planUpdate(at: 1, code: "wqiy", position: nil) == .failure(.alreadyInDict))
    }

    // MARK: 大词库

    /// 一份很大的个人词库：一半写了编码，一半没写（要补自动编码）。词都是用夹具里的字拼的三字词
    static func bigUserDict(_ n: Int) -> String {
        let chars = Array("张三丰五仰泳一二四六七八九十大小山水火木土")
        var lines: [String] = []
        var i = 0
        outer: for a in chars {
            for b in chars {
                for c in chars {
                    guard lines.count < n else { break outer }
                    lines.append(i % 2 == 0 ? "\(a)\(b)\(c)" : "\(a)\(b)\(c)\tabc\(["a", "b", "c", "d"][i % 4])")
                    i += 1
                }
            }
        }
        return WubiFixtures.userDict + "\n" + lines.joined(separator: "\n") + "\n"
    }

    @Test func 个人词库很大时读和换都不慢() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let user = Self.bigUserDict(5000)
        let clock = ContinuousClock()
        var e: WubiEditor?
        let made = try clock.measure { e = try editor(user, in: dir) }
        let editor = try #require(e)
        #expect(editor.userFile.entries.count == 5001)
        // 没写编码的补上了自动编码，进了索引
        #expect(editor.entriesWithCodes.allSatisfy { $0.code != nil })
        var file = editor.userFile
        file.append(DictEntry(text: "甲乙", code: "wqiy"))
        let replaced = clock.measure { _ = editor.replacing(userFile: file) }
        let matched = clock.measure { _ = editor.removeMatches(text: "张三丰", code: nil) }
        // 以前随个人词库大小平方增长（5000 条在 debug 下读、换各要 3 秒多）；现在是线性的，debug 下也远不到 1 秒
        #expect(made < .seconds(1), "读：\(made)")
        #expect(replaced < .seconds(1), "换：\(replaced)")
        #expect(matched < .seconds(1), "找要删的：\(matched)")
    }

    @Test func 换个人词库_索引跟着变() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let e = try editor(in: dir)
        var file = e.userFile
        file.append(DictEntry(text: "甲乙", code: "wqiy", weight: 15))
        let replaced = e.replacing(userFile: file)
        #expect(replaced.userFile == file)
        #expect(replaced.index.words(for: "wqiy").map(\.text) == ["你", "甲乙", "仰泳"])
        #expect(replaced.replacing(userFile: e.userFile).index.words(for: "wqiy").map(\.text) == ["你", "仰泳"])
    }
}
