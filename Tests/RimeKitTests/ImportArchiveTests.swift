import Foundation
import Testing
@testable import RimeKit

@Suite struct ImportArchiveTests {
    typealias T = TransferFixtures

    func exported(_ m: T.Machine) async throws -> URL {
        let file = m.dir.url.appending(path: "e.zip")
        _ = try await m.exporter().export(to: file, packages: [])
        return file
    }

    /// 把一个目录打成 zip（造各种有问题的导出文件）
    func zip(_ build: (URL) throws -> Void, _ m: T.Machine) throws -> URL {
        let content = m.dir.url.appending(path: "craft-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try build(content)
        let file = m.dir.url.appending(path: "craft-\(UUID().uuidString).zip")
        try Zipper().zip(content, to: file)
        return file
    }

    func open(_ file: URL, _ m: T.Machine) throws -> ImportArchive {
        try ImportArchive.open(file, catalog: m.catalog, into: m.dir.url.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func 读出导出的内容() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let a = try open(try await exported(m), m)
        #expect(a.manifest.settings == T.settings)
        #expect(a.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(try String(contentsOf: a.personalDicts[0], encoding: .utf8) == T.pyUser)
        #expect(a.phrases == [T.phrase])
        #expect(a.userDB.keys.sorted() == ["wb_py"])
        #expect(a.warnings.isEmpty)
    }

    @Test func 不是导出文件() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let text = m.dir.url.appending(path: "x.zip")
        try Data("不是 zip".utf8).write(to: text)
        #expect(throws: TransferError.notAnExport(text.path)) { try open(text, m) }
        let noManifest = try zip({ try Data("a".utf8).write(to: $0.appending(path: "a.txt")) }, m)
        #expect(throws: TransferError.notAnExport(noManifest.path)) { try open(noManifest, m) }
        let missing = m.dir.url.appending(path: "none.zip")
        #expect(throws: TransferError.notAnExport(missing.path)) { try open(missing, m) }
    }

    @Test func 格式版本太新() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let file = try zip({ try Data(#"{"formatVersion": 2}"#.utf8).write(to: $0.appending(path: "manifest.json")) }, m)
        #expect(throws: TransferError.unsupportedFormat(2)) { try open(file, m) }
    }

    @Test func 设置里的方案不认识() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let manifest = ExportManifest(formatVersion: 1, exportedAt: T.date, settings: Settings(schemas: ["nope"]),
                                      packages: [], personalDicts: [], phrases: 0, userDB: [])
        let file = try zip({ try JSONCoding.encoder.encode(manifest).write(to: $0.appending(path: "manifest.json")) }, m)
        do {
            _ = try open(file, m)
            Issue.record("应该报错")
        } catch let TransferError.badSettings(message) {
            #expect(message.contains("nope"))
        }
    }

    @Test func 奇怪的文件跳过() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let good = m.dir.url.appending(path: "good", directoryHint: .isDirectory)
        try Unzipper().unzip(try await exported(m), into: good)
        let fm = FileManager.default
        try Data("笔记".utf8).write(to: good.appending(path: "personal/dicts/notes.txt"))
        try fm.createSymbolicLink(atPath: good.appending(path: "personal/dicts/link.dict.yaml").path, withDestinationPath: "/etc/hosts")
        try fm.createDirectory(at: good.appending(path: "personal/dicts/sub.dict.yaml"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: good.appending(path: "userdb/a b.userdb.txt"))
        try Data("x".utf8).write(to: good.appending(path: "userdb/.DS_Store"))
        let file = m.dir.url.appending(path: "weird.zip")
        try Zipper().zip(good, to: file)
        let a = try open(file, m)
        #expect(a.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(a.userDB.keys.sorted() == ["wb_py"])
        #expect(a.warnings.count == 4, "\(a.warnings)")
    }
}
