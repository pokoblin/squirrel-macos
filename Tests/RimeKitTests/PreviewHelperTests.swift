import Foundation
import Testing
@testable import RimeKit

/// 启动真的辅助程序（rime-preview-helper），在编译好的临时配置上打字。没装鼠须管时跳过。
@Suite(.enabled(if: RimeTools.installed))
struct PreviewHelperTests {
    /// 每个测试一份新编译的配置和一个新的辅助程序
    private func withHelper(
        arguments: [String] = [],
        _ body: (HelperProcess, URL, URL) throws -> Void
    ) throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url)
        let helper = try HelperProcess(helper: PreviewFixtures.helper, arguments: arguments)
        defer { _ = helper.closeInput() }
        try body(helper, rime, dir.url)
    }

    @Test func 出候选() throws {
        try withHelper { h, rime, _ in
            let open = try h.send(.open(userDir: rime.path, schema: "py"))
            #expect(open.ok && open.librimeVersion?.hasPrefix("1.") == true, "\(open)")
            #expect(open.state == .empty || open.state?.candidates.isEmpty == true)
            let r = try h.send(.input("nihao"))
            #expect(r.ok)
            #expect(r.librimeVersion == nil)
            #expect(r.state?.candidates.first?.text == "你好" && r.state?.preedit.isEmpty == false, "\(r)")
            #expect(r.state?.committed == nil)
        }
    }

    @Test func 翻页和本页选词() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let first = try h.send(.input("yi"))
            #expect(first.state?.pageNo == 0)
            #expect(first.state?.candidates.map(\.text) == Array(PreviewFixtures.yiCharacters[0..<5]), "\(first)")
            #expect(first.state?.isLastPage == false)

            let down = try h.send(.key(.pageDown))
            #expect(down.state?.pageNo == 1, "\(down)")
            #expect(down.state?.candidates.map(\.text) == Array(PreviewFixtures.yiCharacters[5..<10]))
            let up = try h.send(.key(.pageUp))
            #expect(up.state?.pageNo == 0, "\(up)")

            let again = try h.send(.key(.pageDown))
            let second = try #require(again.state?.candidates[1].text)
            #expect(second == "揖")
            let picked = try h.send(.select(1))
            #expect(picked.state?.committed == second, "\(picked)")
            #expect(picked.state?.candidates.isEmpty == true)
        }
    }

    @Test func 特殊键() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let typed = try h.send(.input("nih"))
            let back = try h.send(.key(.backspace))
            let before = try #require(typed.state?.preedit)
            let after = try #require(back.state?.preedit)
            #expect(after.count < before.count, "\(before) → \(after)")
            let esc = try h.send(.key(.escape))
            #expect(esc.state?.preedit.isEmpty == true && esc.state?.candidates.isEmpty == true, "\(esc)")

            // 回车上屏原编码
            _ = try h.send(.input("ni"))
            let ret = try h.send(.key(.return))
            #expect(ret.state?.committed == "ni", "\(ret)")
            #expect(ret.state?.candidates.isEmpty == true)

            // 上下方向键移动高亮
            _ = try h.send(.input("yi"))
            let down = try h.send(.key(.down))
            #expect(down.state?.highlighted == 1, "\(down)")
            let up = try h.send(.key(.up))
            #expect(up.state?.highlighted == 0, "\(up)")
        }
    }

    @Test func 空格上屏() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "wb")).ok)
            let g = try h.send(.input("g"))
            #expect(g.state?.candidates.first?.text == "一", "\(g)")
            let space = try h.send(.input(" "))
            #expect(space.state?.committed == "一", "\(space)")
            #expect(space.state?.candidates.isEmpty == true)
        }
    }

    @Test func 方案不存在() throws {
        try withHelper { h, rime, _ in
            let nope = try h.send(.open(userDir: rime.path, schema: "nope"))
            #expect(!nope.ok && nope.error?.kind == .schemaMissing, "\(nope)")

            // 副本里缺了编译结果（复制时鼠须管正在部署）
            try FileManager.default.removeItem(at: rime.appending(path: "build/py.schema.yaml"))
            let py = try h.send(.open(userDir: rime.path, schema: "py"))
            #expect(!py.ok && py.error?.kind == .schemaMissing, "\(py)")

            // 打开失败以后不算打开
            #expect(try h.send(.input("g")).error?.kind == .notOpen)
        }
    }

    @Test func 换方案换目录() throws {
        try withHelper { h, rime, dir in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            #expect(try h.send(.input("nihao")).state?.candidates.first?.text == "你好")
            #expect(try h.send(.open(userDir: rime.path, schema: "wb")).ok)
            let g = try h.send(.input("g"))
            #expect(g.state?.candidates.first?.text == "一", "\(g)")

            let copy = dir.appending(path: "rime-copy", directoryHint: .isDirectory)
            try FileManager.default.copyItem(at: rime, to: copy)
            let open = try h.send(.open(userDir: copy.path, schema: "py"))
            #expect(open.ok && open.librimeVersion != nil, "\(open)")
            #expect(open.state?.candidates.isEmpty == true)
            #expect(try h.send(.input("nihao")).state?.candidates.first?.text == "你好")
        }
    }

    @Test func 拒绝真实目录() throws {
        let helper = try HelperProcess(helper: PreviewFixtures.helper)
        let real = NSHomeDirectory() + "/Library/Rime"
        let r = try helper.send(.open(userDir: real, schema: "py"))
        #expect(!r.ok && r.error?.kind == .refusedDirectory, "\(r)")
        let inside = try helper.send(.open(userDir: real + "/build", schema: "py"))
        #expect(inside.error?.kind == .refusedDirectory)
        #expect(helper.closeInput() == 0)
    }

    @Test func 先open() throws {
        let helper = try HelperProcess(helper: PreviewFixtures.helper)
        for request in [PreviewRequest.input("a"), .key(.escape), .select(0), .clear] {
            let r = try helper.send(request)
            #expect(!r.ok && r.error?.kind == .notOpen, "\(request) → \(r)")
        }
        #expect(helper.closeInput() == 0)
    }

    @Test func 非ASCII是坏请求() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            for text in ["你", "a\u{7f}", "\t", "😀"] {
                let r = try h.send(.input(text))
                #expect(!r.ok && r.error?.kind == .badRequest, "\(text) → \(r)")
            }
            #expect(try h.sendRaw("not json").error?.kind == .badRequest)
            #expect(try h.sendRaw(#"{"op":"fly"}"#).error?.kind == .badRequest)
            #expect(try h.sendRaw(#"{"op":"key","name":"tab"}"#).error?.kind == .badRequest)
            #expect(try h.send(.select(-1)).error?.kind == .badRequest)
            let r = try h.send(.input("nihao"))
            #expect(r.state?.candidates.first?.text == "你好", "\(r)")
        }
    }

    @Test func Lua打印不搞乱协议() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url)
        try Data(#"print("LUA-NOISE")"#.utf8 + [0x0a]).write(to: rime.appending(path: "rime.lua"))
        let h = try HelperProcess(helper: PreviewFixtures.helper)
        let open = try h.send(.open(userDir: rime.path, schema: "py"))
        #expect(open.ok, "\(open)")
        let r = try h.send(.input("nihao"))
        #expect(r.state?.candidates.first?.text == "你好", "\(r)")
        #expect(h.closeInput() == 0)
        // 确实打印了，而且进了 stderr
        #expect(h.stderrText().contains("LUA-NOISE"))
    }

    @Test func 加载失败() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let empty = dir.url.appending(path: "Squirrel.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let rime = dir.url.appending(path: "rime", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
        let h = try HelperProcess(helper: PreviewFixtures.helper, arguments: ["--squirrel", empty.path])
        let r = try h.send(.open(userDir: rime.path, schema: "py"))
        #expect(!r.ok && r.error?.kind == .loadFailed, "\(r)")
        #expect(r.error?.message.isEmpty == false)
        // 之后照样回话
        #expect(try h.send(.open(userDir: rime.path, schema: "py")).error?.kind == .loadFailed)
        #expect(h.closeInput() == 0)
    }

    @Test func stdin关闭就退出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url)
        let h = try HelperProcess(helper: PreviewFixtures.helper)
        #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
        #expect(h.closeInput() == 0)
    }
}
