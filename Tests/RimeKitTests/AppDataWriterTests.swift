import Foundation
import Testing
@testable import RimeKit

@Suite struct AppDataWriterTests {
    typealias T = TransferFixtures

    @Test func 写到一半失败时原来的设置和个人内容都还在() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let missing = m.dir.url.appending(path: "gone.dict.yaml")   // 复制它会失败
        #expect(throws: (any Error).self) {
            try AppDataWriter.replace(settings: Settings(schemas: ["py"]), dicts: [missing], phrases: [], paths: m.paths)
        }
        #expect(try SettingsStore(paths: m.paths).load() == T.settings)
        let personal = try PersonalContent.load(from: m.paths)
        #expect(personal.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(personal.phrases == [T.phrase])
        // 不留临时目录
        #expect(try FileManager.default.contentsOfDirectory(atPath: m.paths.root.path).filter { $0.hasPrefix("personal.") } == [])
    }

    @Test func 换掉整个个人内容() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let dict = m.dir.url.appending(path: "wb_user.dict.yaml")
        try Data(GenFixtures.dict("wb_user", ["新词\taaaa"]).utf8).write(to: dict)
        try AppDataWriter.replace(settings: Settings(schemas: ["wb"]), dicts: [dict], phrases: [], paths: m.paths)
        #expect(try SettingsStore(paths: m.paths).load() == Settings(schemas: ["wb"]))
        let personal = try PersonalContent.load(from: m.paths)
        #expect(personal.dicts.map(\.lastPathComponent) == ["wb_user.dict.yaml"])
        #expect(personal.phrases == [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: m.paths.root.path).filter { $0.hasPrefix("personal.") } == [])
    }
}
