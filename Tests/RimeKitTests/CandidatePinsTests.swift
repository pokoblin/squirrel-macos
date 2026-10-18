import Foundation
import Testing
@testable import RimeKit

@Suite struct CandidatePinsTests {
    let kou = Phrase(text: "口", code: "kkkk", weight: nil)
    let address = Phrase(text: "地址", code: "dz", weight: 5)

    func read(_ paths: AppPaths) throws -> String {
        try String(contentsOf: paths.personalPhrases, encoding: .utf8)
    }

    func write(_ paths: AppPaths, _ text: String) throws {
        try FileManager.default.createDirectory(at: paths.personal, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: paths.personalPhrases)
    }

    func recordInLedger(_ paths: AppPaths, _ phrases: [Phrase]?) throws {
        var ledger = Ledger()
        ledger.phrasesSHA256 = phrases.map(PhraseFile.fingerprint)
        try ledger.save(paths)
    }

    // MARK: 置顶、还原（只改列表）

    @Test func 置顶加在末尾并替换同编码的旧条目() {
        let r = CandidatePins.pinning(text: "串口", code: "kkkk", in: [address, kou])
        #expect(r.phrases == [address, Phrase(text: "串口", code: "kkkk", weight: nil)])
        #expect(r.replaced == [kou])
    }

    @Test func 不同编码下置顶同一个字两条都留着() {
        let r = CandidatePins.pinning(text: "口", code: "k", in: [kou])
        #expect(r.phrases == [kou, Phrase(text: "口", code: "k", weight: nil)])
        #expect(r.replaced.isEmpty)
    }

    @Test func 还原只去掉那一条() {
        #expect(CandidatePins.removing(kou, from: [address, kou]) == [address])
    }

    // MARK: 读写 personal/phrases.txt

    @Test func 存了再读保留权重丢掉注释() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try write(paths, "# 注释\n地址\tdz\t5\n")
        let store = PersonalPhraseStore(paths: paths)
        try store.save(CandidatePins.pinning(text: "口", code: "kkkk", in: try store.load()).phrases)
        #expect(try read(paths) == PhraseFile.header + "地址\tdz\t5\n口\tkkkk\n")
        #expect(try store.load() == [address, kou])
    }

    @Test func 存空列表删掉文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let store = PersonalPhraseStore(paths: paths)
        #expect(try store.load() == [])
        try store.save([kou])
        try store.save([])
        #expect(!FileManager.default.fileExists(atPath: paths.personalPhrases.path))
        #expect(try store.load() == [])
        try store.save([])   // 本来就没有文件也不算错
    }

    @Test func 正在应用时不能写() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        #expect(throws: ApplyError.busy) { try PersonalPhraseStore(paths: paths).save([kou]) }
        #expect(!FileManager.default.fileExists(atPath: paths.personalPhrases.path))
    }

    // MARK: 有没应用的改动

    @Test func 有没应用的改动按账本里的指纹算() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let store = PersonalPhraseStore(paths: paths)
        #expect(!store.needsApply())   // 没有账本、没有文件
        try store.save([kou])
        #expect(store.needsApply())
        try recordInLedger(paths, [kou])
        #expect(!store.needsApply())
        try store.save([])
        #expect(store.needsApply())    // 账本说上次应用时有一条
    }

    @Test func 账本没有指纹字段时当作上次没有短语() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try recordInLedger(paths, nil)
        let store = PersonalPhraseStore(paths: paths)
        #expect(!store.needsApply())
        try store.save([kou])
        #expect(store.needsApply())
    }

    @Test func 指纹只看短语内容() {
        #expect(PhraseFile.fingerprint([]) == PhraseFile.fingerprint([]))
        #expect(PhraseFile.fingerprint([kou]) != PhraseFile.fingerprint([]))
        #expect(PhraseFile.fingerprint([kou, address]) != PhraseFile.fingerprint([address, kou]))
    }
}
