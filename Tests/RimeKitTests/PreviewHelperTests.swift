import Foundation
import Testing
@testable import RimeKit

/// 启动真的辅助程序（rime-preview-helper），在编译好的临时配置上打字。没装鼠须管时跳过。
@Suite(.enabled(if: RimeTools.installed))
struct PreviewHelperTests {
    /// 每个测试一份新编译的配置和一个新的辅助程序
    private func withHelper(
        arguments: [String] = [],
        extraFiles: [String: String] = [:],
        _ body: (HelperProcess, URL, URL) throws -> Void
    ) throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url, extraFiles: extraFiles)
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

    @Test func 回原始输入和整段标记() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let r = try h.send(.input("nihao"))
            #expect(r.state?.input == "nihao", "\(r)")
            #expect(r.state?.wholeInput == true, "\(r)")
            let cleared = try h.send(.clear)
            #expect(cleared.state?.input == "" && cleared.state?.wholeInput == false, "\(cleared)")
        }
    }

    @Test func 查开关() throws {
        let switches = "patch:\n  switches:\n    - name: test_on\n      reset: 1\n    - name: test_off\n      reset: 0\n"
        try withHelper(extraFiles: ["py.custom.yaml": switches]) { h, rime, _ in
            let early = try h.send(.option("test_on"))
            #expect(!early.ok && early.error?.kind == .notOpen, "\(early)")
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let on = try h.send(.option("test_on"))
            #expect(on.ok && on.option == true, "\(on)")
            #expect(try h.send(.option("test_off")).option == false)
            #expect(try h.send(.option("ascii_mode")).option == false)
        }
    }

    @Test func 只对应前一段编码的候选不算整段() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let typed = try h.send(.input("nihao"))
            let texts = typed.state?.candidates.map(\.text) ?? []
            let whole = try #require(texts.firstIndex(of: "你好"), "\(texts)")
            let part = try #require(texts.firstIndex(of: "你"), "\(texts)")
            let yes = try h.send(.covers(whole))
            #expect(yes.ok && yes.covers == true, "\(yes)")
            let no = try h.send(.covers(part))
            #expect(no.ok && no.covers == false, "\(no)")
            // 查完正在打的东西不变
            #expect(no.state?.input == "nihao" && no.state?.candidates.map(\.text) == texts, "\(no)")
        }
    }

    @Test func 通过会话查开关以后还能打字() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url)
        let session = PreviewSession(helper: PreviewFixtures.helper)
        _ = try await session.open(userDir: rime, schema: "py")
        #expect(try await session.option("ascii_mode") == false)
        let state = try await session.input("nihao")
        #expect(state.candidates.first?.text == "你好")
        #expect(try await session.covers(0) == true)
        #expect(try await session.input("").candidates.first?.text == "你好")
        await session.close()
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

    /// librime 不处理的字符（process_key 返回 0），鼠须管会原样交给正在打字的程序：试打里接在上屏文字后面
    @Test func 不处理的字符原样上屏() throws {
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            // 没有编码时打数字、空格、标点（测试方案没有 punctuator）
            for text in ["3", " ", ",", "."] {
                let r = try h.send(.input(text))
                #expect(r.state?.committed == text, "\(text) → \(r)")
            }
            // 先上屏的字在前，没处理的字符在后，顺序不乱
            let mixed = try h.send(.input("yi 3"))
            #expect(mixed.state?.committed == "一3", "\(mixed)")
            // 有编码时打标点：express_editor 先把首选上屏，标点照样原样上屏
            let punct = try h.send(.input("ni,"))
            #expect(punct.state?.committed == "你,", "\(punct)")
            #expect(punct.state?.preedit.isEmpty == true)
            // 有候选时打数字是选词（selector 处理了），不额外上屏数字
            let pick = try h.send(.input("yi3"))
            #expect(pick.state?.committed == "医", "\(pick)")
            // 有编码但没有候选（测试词库里没有 wo）时打数字：selector 照样吃掉，什么也不上屏
            let none = try h.send(.input("wo3"))
            #expect(none.state?.committed == nil && none.state?.preedit == "wo", "\(none)")
        }
    }

    /// 方案设了 menu/alternative_select_keys、没设 alternative_select_labels：序号用选词键的字符（和鼠须管一样）
    @Test func 选词键当序号() throws {
        let patch = "patch:\n  menu/alternative_select_keys: \"67890\"\n"
        try withHelper(extraFiles: ["py.custom.yaml": patch]) { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let yi = try h.send(.input("yi"))
            #expect(yi.state?.labels == ["6", "7", "8", "9", "0"], "\(yi)")
            // 选词键真的生效：7 选第二个
            let picked = try h.send(.input("7"))
            #expect(picked.state?.committed == PreviewFixtures.yiCharacters[1], "\(picked)")
        }
        // 都没设：labels 是 nil，界面用 1、2、3……
        try withHelper { h, rime, _ in
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let yi = try h.send(.input("yi"))
            #expect(yi.state?.candidates.isEmpty == false && yi.state?.labels == nil, "\(yi)")
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

            // 第二份配置每页 3 个候选：换目录真的生效了才会看到 3 个
            let second = try PreviewFixtures.compiledConfig(in: dir.appending(path: "second"), pageSize: 3)
            let open = try h.send(.open(userDir: second.path, schema: "py"))
            #expect(open.ok && open.librimeVersion != nil, "\(open)")
            #expect(open.state?.candidates.isEmpty == true)
            let yi3 = try h.send(.input("yi"))
            #expect(yi3.state?.candidates.map(\.text) == Array(PreviewFixtures.yiCharacters[0..<3]), "\(yi3)")
            #expect(try h.send(.input("nihao")).ok)

            // 换回第一份，又是每页 5 个
            #expect(try h.send(.open(userDir: rime.path, schema: "py")).ok)
            let yi5 = try h.send(.input("yi"))
            #expect(yi5.state?.candidates.map(\.text) == Array(PreviewFixtures.yiCharacters[0..<5]), "\(yi5)")
        }
    }

    @Test func 拒绝真实目录() throws {
        // 用一个空的「鼠须管」，librime 根本加载不了：就算保险失效，测试也不会让 librime 碰真实目录。
        // 回的是 refusedDirectory 而不是 loadFailed，说明先查目录、再报加载错误
        let dir = try TempDir(); defer { dir.remove() }
        let helper = try HelperProcess(helper: PreviewFixtures.helper, arguments: ["--squirrel", dir.url.path])
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
