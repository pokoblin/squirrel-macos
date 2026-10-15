import Foundation
import Testing
@testable import RimeKit

/// 用宿主机上鼠须管自带的 rime_dict_manager，只在临时目录里运行（它把当前目录当 Rime 用户目录）
@Suite(.enabled(if: RimeTools.installed))
struct RimeDictManagerTests {
    static let snapshot = """
        # Rime user dictionary export
        #@/db_name\ttest
        #@/db_type\tuserdb
        #@/rime_version\t1.16.0
        #@/user_id\tunknown
        ni hao \t你好\t0
        ce shi \t测试\t0

        """

    func manager(_ dir: TempDir) -> RimeDictManager {
        RimeDictManager(tool: URL(fileURLWithPath: RimeTools.squirrel + "/MacOS/rime_dict_manager"),
                        rimeDirectory: dir.url.appending(path: "Rime", directoryHint: .isDirectory))
    }

    @Test func 空目录里没有输入习惯() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try manager(dir).list() == [])
    }

    @Test func 还没有数据库时也能导入_导入两次是合并() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let m = manager(dir)
        let file = dir.url.appending(path: "in.txt")
        try Data(Self.snapshot.utf8).write(to: file)
        try m.importSnapshot("test", from: file)
        #expect(try m.list() == ["test"])
        let first = dir.url.appending(path: "out1.txt")
        try m.export("test", to: first)
        try m.importSnapshot("test", from: file)
        let second = dir.url.appending(path: "out2.txt")
        try m.export("test", to: second)
        let text = try String(contentsOf: first, encoding: .utf8)
        #expect(text.contains("你好"))
        #expect(text.contains("测试"))
        #expect(try String(contentsOf: second, encoding: .utf8) == text)
    }

    @Test func 名字不对就不运行() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(throws: UserDBError.badName("../x")) { try manager(dir).export("../x", to: dir.url.appending(path: "o.txt")) }
        #expect(RimeDictManager.isValidName("rime_ice"))
        #expect(RimeDictManager.isValidName("wubi86_jidian"))
        #expect(!RimeDictManager.isValidName(""))
        #expect(!RimeDictManager.isValidName(".hidden"))
        #expect(!RimeDictManager.isValidName("a b"))
        #expect(!RimeDictManager.isValidName("a/b"))
    }

    @Test func 导出不存在的输入习惯会报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(throws: UserDBError.self) { try manager(dir).export("nothing", to: dir.url.appending(path: "o.txt")) }
    }
}
