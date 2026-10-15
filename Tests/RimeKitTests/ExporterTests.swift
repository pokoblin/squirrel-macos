import Foundation
import Testing
@testable import RimeKit

@Suite struct ExporterTests {
    typealias T = TransferFixtures

    func unzip(_ file: URL, _ m: T.Machine) throws -> URL {
        let out = m.dir.url.appending(path: "unzipped", directoryHint: .isDirectory)
        try Unzipper().unzip(file, into: out)
        return out
    }

    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @Test func 导出设置个人内容和输入习惯() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let target = m.dir.url.appending(path: "out/e.zip")
        let report = try await m.exporter().export(to: target, packages: [ExportManifest.Package(id: "wubi", version: "v1")])
        let out = try unzip(target, m)
        #expect(try T.files(in: out) == ["manifest.json", "personal/dicts/py_user.dict.yaml", "personal/phrases.txt", "userdb/wb_py.userdb.txt"])
        let manifest = try JSONCoding.decoder.decode(ExportManifest.self, from: Data(contentsOf: out.appending(path: "manifest.json")))
        #expect(manifest == report.manifest)
        #expect(manifest == ExportManifest(formatVersion: 1, exportedAt: T.date, settings: T.settings,
                                           packages: [ExportManifest.Package(id: "wubi", version: "v1")],
                                           personalDicts: ["py_user.dict.yaml"], phrases: 1, userDB: ["wb_py"]))
        #expect(try read(out.appending(path: "personal/dicts/py_user.dict.yaml")) == T.pyUser)
        #expect(PhraseFile.parse(try read(out.appending(path: "personal/phrases.txt"))) == [T.phrase])
        #expect(try read(out.appending(path: "userdb/wb_py.userdb.txt")) == T.snapshot)
        #expect(m.squirrel.calls == ["quit", "launch"])
        #expect(report.warnings.isEmpty)
    }

    @Test func 不带输入习惯() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let target = m.dir.url.appending(path: "e.zip")
        let report = try await m.exporter(userDB: false).export(to: target, packages: [])
        #expect(report.manifest.userDB == [])
        #expect(!(try T.files(in: try unzip(target, m)).contains { $0.hasPrefix("userdb/") }))
        #expect(m.squirrel.calls == [])
    }

    @Test func 没有设置不能导出() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        await #expect(throws: TransferError.noSettings) {
            try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        }
    }

    @Test func 已有文件不覆盖_除非指定() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let target = m.dir.url.appending(path: "e.zip")
        try Data("旧的".utf8).write(to: target)
        await #expect(throws: TransferError.targetExists(target.path)) {
            try await m.exporter().export(to: target, packages: [])
        }
        _ = try await m.exporter().export(to: target, packages: [], overwrite: true)
        #expect(try T.files(in: try unzip(target, m)).contains("manifest.json"))
    }

    @Test func 个人词库在应用外改过时提醒() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["py_user.dict.yaml": LedgerEntry(sha256: "0", origin: "personal")]).save(m.paths)
        try FileManager.default.createDirectory(at: m.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("外面改过的".utf8).write(to: m.locations.rimeDirectory.appending(path: "py_user.dict.yaml"))
        let report = try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        #expect(report.warnings.contains { $0.contains("py_user.dict.yaml") && $0.contains("--adopt-personal") })
    }

    @Test func 暂存区用完就删() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        _ = try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: m.paths.staging.path).isEmpty)
    }
}
