import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTextReplacementTests {
    typealias T = TransferFixtures

    /// 用户在系统设置里改文本替换：测试里随时换内容
    final class Replacements: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TextReplacementSnapshot
        var failing = false
        init(_ phrases: [Phrase], badShortcut: Int = 0) {
            value = TextReplacementSnapshot(usable: phrases, badShortcut: badShortcut, badPhrase: 0)
        }
        func set(_ phrases: [Phrase]) { lock.withLock { value = TextReplacementSnapshot(usable: phrases, badShortcut: 0, badPhrase: 0) } }
        func get() throws -> TextReplacementSnapshot {
            struct Unreadable: Error, CustomStringConvertible { var description: String { "数据库打不开" } }
            if failing { throw Unreadable() }
            return lock.withLock { value }
        }
    }

    struct CLI {
        let machine: T.Machine
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", machine.locations.rimeDirectory.path, "--cache-only"], context)
        }

        var phraseFile: String {
            (try? String(contentsOf: machine.locations.rimeDirectory.appending(path: "custom_phrase.txt"), encoding: .utf8)) ?? ""
        }

        var settings: Settings? { try? SettingsStore(paths: machine.paths).load() }
    }

    let a = Phrase(text: "替换甲", code: "tha", weight: 1)
    let b = Phrase(text: "替换乙", code: "thb", weight: 1)

    func cli(_ m: T.Machine, _ r: Replacements) -> CLI {
        let output = Output(echo: false)
        let catalog = m.catalog
        var context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: m.paths, output: output,
            locations: m.locations, compiler: FakeCompiler(), squirrel: m.squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in })
        context.textReplacementSnapshot = { try r.get() }
        context.userDBTool = m.tool
        return CLI(machine: m, output: output, context: context)
    }

    @Test func 看状态_同步没打开() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let c = cli(m, Replacements([a], badShortcut: 2))
        #expect(await c.run(["textreplacement", "status"]) == 0)
        #expect(c.output.text.contains("1 条能用"))
        #expect(c.output.text.contains("2 条快捷码里有数字或符号"))
        #expect(c.output.text.contains("没打开"))
    }

    @Test func 同步后看得出新增_再同步就一样了() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "sync"]) == 0)
        #expect(c.output.text.contains("部署完成"))
        #expect(c.settings?.textReplacement.sync == true)
        #expect(c.settings?.textReplacement.syncedEntries == TextReplacementSync.entryHashes([a]))
        #expect(c.phraseFile.contains(a.line))
        #expect(c.phraseFile.contains(T.phrase.line))   // 手动短语还在

        let c2 = cli(m, r)
        #expect(await c2.run(["textreplacement", "status"]) == 0)
        #expect(c2.output.text.contains("和上次同步时一样"))

        r.set([a, b])   // 用户在系统设置里加了一条
        let c3 = cli(m, r)
        #expect(await c3.run(["textreplacement", "status"]) == 0)
        #expect(c3.output.text.contains("新增 1 条，删掉 0 条"))
        #expect(await c3.run(["textreplacement", "sync"]) == 0)
        #expect(c3.phraseFile.contains(b.line))

        let c4 = cli(m, r)
        #expect(await c4.run(["textreplacement", "status"]) == 0)
        #expect(c4.output.text.contains("和上次同步时一样"))
    }

    @Test func 改别的设置时也带上最新的文本替换并记下() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        r.set([a, b])
        let c = cli(m, r)
        #expect(await c.run(["apply"]) == 0)
        #expect(c.phraseFile.contains(b.line))
        #expect(c.settings?.textReplacement.syncedEntries == TextReplacementSync.entryHashes([a, b]))
    }

    @Test func 关掉同步去掉文本替换的短语_手动短语还在() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "off"]) == 0)
        #expect(c.settings?.textReplacement == TextReplacementSettings(sync: false))
        #expect(!c.phraseFile.contains(a.line))
        #expect(c.phraseFile.contains(T.phrase.line))
    }

    @Test func 读不了时报错_不悄悄去掉已经同步的短语() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        r.failing = true
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "status"]) == 1)
        #expect(await c.run(["apply"]) == 1)
        #expect(c.output.text.contains("数据库打不开"))
        #expect(c.phraseFile.contains(a.line))
    }

    @Test func 输出里没有文本替换的内容() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "sync"]) == 0)
        r.set([a, b])
        #expect(await c.run(["textreplacement", "status"]) == 0)
        for secret in [a.text, a.code, b.text, b.code] {
            #expect(!c.output.text.contains(secret), "输出里有「\(secret)」")
        }
    }

    @Test func 打印设置时不打印同步记录() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        let c = cli(m, r)
        #expect(await c.run(["settings", "show"]) == 0)
        #expect(c.output.text.contains("\"sync\" : true"))
        #expect(!c.output.text.contains("syncedEntries"))
        #expect(!c.output.text.contains("lastSyncedHash"))
    }

    @Test func 没有设置时() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let c = cli(m, Replacements([a]))
        #expect(await c.run(["textreplacement", "status"]) == 1)
        #expect(c.output.text.contains("还没有设置"))
    }
}
