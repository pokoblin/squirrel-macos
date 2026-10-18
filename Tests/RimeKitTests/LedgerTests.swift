import Foundation
import Testing
@testable import RimeKit

@Suite struct LedgerTests {
    func write(_ dir: URL, _ path: String, _ text: String) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func sha(_ text: String) -> String { Hashing.sha256(of: Data(text.utf8)) }

    @Test func 没有文件时是空的存了再读不变() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        #expect(try Ledger.load(paths) == Ledger())
        let ledger = Ledger(entries: ["a.yaml": LedgerEntry(sha256: sha("a"), origin: "generated")],
                            appliedAt: Date(timeIntervalSince1970: 1_000))
        try ledger.save(paths)
        #expect(try Ledger.load(paths) == ledger)
    }

    @Test func 老账本没有短语指纹() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try write(paths.root, paths.ledgerFile.lastPathComponent, #"{"formatVersion":1,"entries":{}}"#)
        #expect(try Ledger.load(paths).phrasesSHA256 == nil)
        var ledger = Ledger()
        ledger.phrasesSHA256 = sha("口\tkkkk\n")
        try ledger.save(paths)
        #expect(try Ledger.load(paths).phrasesSHA256 == sha("口\tkkkk\n"))
    }

    @Test func 发现改过和删了的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "same.yaml", "same")
        try write(rime, "changed.yaml", "new")
        let ledger = Ledger(entries: [
            "same.yaml": LedgerEntry(sha256: sha("same"), origin: "generated"),
            "changed.yaml": LedgerEntry(sha256: sha("old"), origin: "package:x"),
            "gone.yaml": LedgerEntry(sha256: sha("gone"), origin: "personal"),
        ])
        #expect(ledger.externalChanges(in: rime) == [.modified("changed.yaml"), .deleted("gone.yaml")])
    }

    @Test func 要覆盖应用不管的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "managed.yaml", "m")
        try write(rime, "theirs.yaml", "t")
        let ledger = Ledger(entries: ["managed.yaml": LedgerEntry(sha256: sha("m"), origin: "generated")])
        #expect(ledger.unmanagedOverwrites(["managed.yaml", "theirs.yaml", "new.yaml"], in: rime) == [.unmanaged("theirs.yaml")])
    }

    @Test func 来源的写法() {
        #expect(FileOrigin.package("rime-ice").ledgerValue == "package:rime-ice")
        #expect(FileOrigin.generated.ledgerValue == "generated")
        #expect(FileOrigin.personal.ledgerValue == "personal")
    }

    @Test func 说明是中文() {
        #expect(ExternalChange.modified("a.yaml").description == "a.yaml：在应用外被改过")
        #expect(ExternalChange.deleted("a.yaml").description == "a.yaml：在应用外被删了")
        #expect(ExternalChange.unmanaged("a.yaml").description == "a.yaml：不是应用写的，这次会被覆盖")
    }

    @Test func 不认识的格式版本() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":9,"entries":{}}"#.utf8).write(to: paths.ledgerFile)
        #expect(throws: LedgerError.unsupportedFormat(9)) { try Ledger.load(paths) }
    }
}

@Suite struct LedgerPackagesTests {
    @Test func 以前的账本没有包版本也能读() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":1,"entries":{}}"#.utf8).write(to: paths.ledgerFile)
        let ledger = try Ledger.load(paths)
        #expect(ledger.packages == nil)
        var next = ledger
        next.packages = ["wubi": "abc"]
        try next.save(paths)
        #expect(try Ledger.load(paths).packages == ["wubi": "abc"])
    }
}
