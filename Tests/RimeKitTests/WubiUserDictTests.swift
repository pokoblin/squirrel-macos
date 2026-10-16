import Foundation
import Testing
@testable import RimeKit

@Suite struct WubiUserDictTests {
    /// 一套临时环境：应用数据目录、假的 Rime 目录、缓存里的迷你极点五笔包
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let rime: URL
        let package: CachedPackage
        let store: WubiUserDict

        init() throws {
            dir = try TempDir()
            paths = Fixtures.paths(dir)
            rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
            package = try WubiFixtures.makePackage(in: dir.url.appending(path: "cache", directoryHint: .isDirectory))
            let locations = RimeLocations(
                rimeDirectory: rime,
                squirrelApp: dir.url.appending(path: "no-squirrel.app", directoryHint: .isDirectory),
                logDirectory: dir.url.appending(path: "log", directoryHint: .isDirectory))
            store = WubiUserDict(paths: paths, locations: locations)
        }

        var rimeFile: URL { rime.appending(path: WubiFixtures.userName) }
        var personalFile: URL { paths.personalDicts.appending(path: WubiFixtures.userName) }

        func writeRime(_ text: String) throws {
            try Data(text.utf8).write(to: rimeFile)
        }

        func writePersonal(_ text: String) throws {
            try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: personalFile)
        }

        /// 账本里个人词库这一条记成 text 的哈希
        func record(_ text: String) throws {
            var ledger = try Ledger.load(paths)
            ledger.entries[WubiFixtures.userName] = LedgerEntry(sha256: sha(text), origin: "personal")
            try ledger.save(paths)
        }
    }

    static func sha(_ text: String) -> String { Hashing.sha256(of: Data(text.utf8)) }
    func sha(_ text: String) -> String { Self.sha(text) }

    static let personalWithWord = WubiFixtures.userDict + "\n甲乙丙\tlnxy\n"
    static let rimeWithOutsideWord = WubiFixtures.userDict + "\n丁戊己\tsdnn\n"

    // MARK: 起点

    @Test func 起点用包里的() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(WubiFixtures.userDict)
        let file = try env.store.load(package: env.package)
        #expect(file.render() == WubiFixtures.userDict)
        #expect(!FileManager.default.fileExists(atPath: env.paths.personal.path))

        // Rime 目录里没有这个文件时也用包里的
        try FileManager.default.removeItem(at: env.rimeFile)
        #expect(try env.store.load(package: env.package).render() == WubiFixtures.userDict)
        #expect(!FileManager.default.fileExists(atPath: env.paths.personal.path))
    }

    @Test func 起点用Rime目录里手改过的() throws {
        let env = try Env(); defer { env.dir.remove() }
        let edited = WubiFixtures.userDict + "\n手改一\taaaa\n手改二\tbbbb\t5\n"
        try env.writeRime(edited)
        let file = try env.store.load(package: env.package)
        #expect(file.entries.contains(DictEntry(text: "手改一", code: "aaaa")))
        #expect(file.entries.contains(DictEntry(text: "手改二", code: "bbbb", weight: 5)))
        #expect(file.render() == edited)
        #expect(!FileManager.default.fileExists(atPath: env.paths.personal.path))
    }

    @Test func 有personal里的就读它() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(Self.rimeWithOutsideWord)
        try env.writePersonal(Self.personalWithWord)
        #expect(try env.store.load(package: env.package).render() == Self.personalWithWord)
    }

    @Test func 保存写进personal头部保留version() throws {
        let env = try Env(); defer { env.dir.remove() }
        var file = try env.store.load(package: env.package)
        file.append(DictEntry(text: "甲乙丙", code: "lnxy"))
        try env.store.save(file)
        let saved = try TextFile.read(env.personalFile)
        #expect(saved == file.render())
        #expect(saved.contains("version: \"test\""))
        // 没有留下临时文件
        let names = try FileManager.default.contentsOfDirectory(atPath: env.paths.personalDicts.path)
        #expect(names == [WubiFixtures.userName])
        // 再存一次（覆盖）也行
        file.append(DictEntry(text: "丁戊己", code: "sdnn"))
        try env.store.save(file)
        #expect(try env.store.load(package: env.package).entries.count == 3)
    }

    // MARK: 有没有没应用的改动

    @Test func 保存后需要应用() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(WubiFixtures.userDict)
        try env.record(WubiFixtures.userDict)
        // 还没有 personal 里的文件：没有要应用的
        #expect(!env.store.needsApply())

        var file = try env.store.load(package: env.package)
        file.append(DictEntry(text: "甲乙丙", code: "lnxy"))
        try env.store.save(file)
        #expect(env.store.needsApply())

        try env.record(file.render())
        #expect(!env.store.needsApply())
    }

    @Test func 账本里没有这个文件时保存后需要应用() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.store.save(try env.store.load(package: env.package))
        #expect(env.store.needsApply())
    }

    // MARK: 外部改动

    @Test func 外部改动和合并() throws {
        let env = try Env(); defer { env.dir.remove() }
        // 上次应用写进去的是包里那份
        try env.writeRime(WubiFixtures.userDict)
        try env.record(WubiFixtures.userDict)
        #expect(!env.store.externalChange())

        // 应用里加了「甲乙丙」
        var file = try env.store.load(package: env.package)
        file.append(DictEntry(text: "甲乙丙", code: "lnxy"))
        try env.store.save(file)

        // 应用外在 Rime 目录那份里加了「丁戊己」
        try env.writeRime(Self.rimeWithOutsideWord)
        #expect(env.store.externalChange())

        let before = try env.store.load(package: env.package)
        let result = try env.store.mergeExternal(into: before)
        let (merged, added) = (result.merged, result.added)
        #expect(result.sourceSHA256 == sha(Self.rimeWithOutsideWord))
        #expect(added == 1)
        #expect(merged.entries.map(\.text) == ["分组词条", "甲乙丙", "丁戊己"])
        // 原有的行（头部、## 示例 分组行、原来的词条）原样不变，新词在末尾
        #expect(merged.render().hasPrefix(before.render()))
        #expect(merged.render().contains("## 示例\n分组词条\twxyt\n"))
        #expect(merged.render().hasSuffix("丁戊己\tsdnn\n"))

        try env.store.save(merged)
        try env.store.acknowledgeExternal(expectedSHA256: result.sourceSHA256)
        #expect(!env.store.externalChange())
        let ledger = try Ledger.load(env.paths)
        #expect(!ledger.externalChanges(in: env.rime).map(\.path).contains(WubiFixtures.userName))
        #expect(ledger.entries[WubiFixtures.userName]?.origin == "personal")
        // personal 里的合并版和 Rime 目录里的不一样：还要应用
        #expect(env.store.needsApply())
    }

    @Test func 账本里没有这个路径不算外部改动() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(Self.rimeWithOutsideWord)
        #expect(!env.store.externalChange())
    }

    @Test func 合并时同词同码不重复() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(WubiFixtures.userDict + "\n甲乙丙\tlnxy\t5\n无码词\n丁戊己\tsdnn\n丁戊己\tsdnn\n同词异码\tqqqq\n")
        let mine = try DictFile.parse(WubiFixtures.userDict + "\n甲乙丙\tlnxy\n无码词\taaaa\n同词异码\twwww\n")
        let result = try env.store.mergeExternal(into: mine)
        let (merged, added) = (result.merged, result.added)
        // 甲乙丙：同词同码（权重不同也算同一条）；无码词：没写编码只比词；丁戊己：外面写了两遍只加一条
        #expect(added == 2)
        #expect(merged.entries.suffix(2) == [
            DictEntry(text: "丁戊己", code: "sdnn"),
            DictEntry(text: "同词异码", code: "qqqq"),
        ])
        #expect(merged.entries.filter { $0.text == "甲乙丙" }.count == 1)
    }

    @Test func 合并后外面又改了不记账() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(WubiFixtures.userDict)
        try env.record(WubiFixtures.userDict)
        try env.writeRime(Self.rimeWithOutsideWord)
        let result = try env.store.mergeExternal(into: try DictFile.parse(WubiFixtures.userDict))
        #expect(result.added == 1)

        // 等用户点按钮的时候，外面又加了一个词
        let again = Self.rimeWithOutsideWord + "庚辛壬\tyuyu\n"
        try env.writeRime(again)
        #expect(throws: WubiUserDictError.changedAgain) {
            try env.store.acknowledgeExternal(expectedSHA256: result.sourceSHA256)
        }
        // 账本没动：还算外部改动
        #expect(try Ledger.load(env.paths).entries[WubiFixtures.userName]?.sha256 == sha(WubiFixtures.userDict))
        #expect(env.store.externalChange())

        // 重新合并后可以记账，两个外面的词都收进来了
        let second = try env.store.mergeExternal(into: result.merged)
        #expect(second.added == 1)
        #expect(second.merged.entries.map(\.text) == ["分组词条", "丁戊己", "庚辛壬"])
        try env.store.acknowledgeExternal(expectedSHA256: second.sourceSHA256)
        #expect(!env.store.externalChange())
    }

    @Test func 外面写了编码这边没写编码的要加进来() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(WubiFixtures.userDict + "\n手编词\tabcd\n")
        let mine = try DictFile.parse(WubiFixtures.userDict + "\n手编词\n")
        let result = try env.store.mergeExternal(into: mine)
        #expect(result.added == 1)
        #expect(result.merged.entries.suffix(2) == [
            DictEntry(text: "手编词"),
            DictEntry(text: "手编词", code: "abcd"),
        ])
    }

    @Test func 外面没写编码这边写了编码的不重复() throws {
        let env = try Env(); defer { env.dir.remove() }
        try env.writeRime(WubiFixtures.userDict + "\n手编词\n")
        let mine = try DictFile.parse(WubiFixtures.userDict + "\n手编词\tabcd\n")
        let result = try env.store.mergeExternal(into: mine)
        #expect(result.added == 0)
        #expect(result.merged == mine)
    }

    @Test func 外面删掉的词不跟着删() throws {
        let env = try Env(); defer { env.dir.remove() }
        // 外面那份把「分组词条」删了
        try env.writeRime("---\nname: wubi86_jidian_user\nversion: \"test\"\nsort: original\n...\n")
        let mine = try DictFile.parse(Self.personalWithWord)
        let result = try env.store.mergeExternal(into: mine)
        let (merged, added) = (result.merged, result.added)
        #expect(added == 0)
        #expect(merged == mine)
        #expect(merged.render() == Self.personalWithWord)
    }

    // MARK: Ledger.acknowledge

    @Test func Ledger的acknowledge只改哈希() {
        var ledger = Ledger(entries: [
            "a.yaml": LedgerEntry(sha256: sha("old"), origin: "personal"),
            "b.yaml": LedgerEntry(sha256: sha("b"), origin: "package:x"),
        ], appliedAt: Date(timeIntervalSince1970: 1_000))
        ledger.acknowledge(path: "a.yaml", sha256: sha("new"))
        #expect(ledger.entries["a.yaml"] == LedgerEntry(sha256: sha("new"), origin: "personal"))
        #expect(ledger.entries["b.yaml"] == LedgerEntry(sha256: sha("b"), origin: "package:x"))
        #expect(ledger.appliedAt == Date(timeIntervalSince1970: 1_000))
        // 没有的路径不加
        ledger.acknowledge(path: "c.yaml", sha256: sha("c"))
        #expect(ledger.entries["c.yaml"] == nil)
        #expect(ledger.entries.count == 2)
    }
}
