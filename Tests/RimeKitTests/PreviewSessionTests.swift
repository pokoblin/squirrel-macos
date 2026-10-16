import Foundation
import Testing
@testable import RimeKit

/// PreviewSession：用假的辅助程序（sh 脚本）测启动、超时、崩溃、乱码，不需要 librime
struct PreviewSessionTests {
    /// 每读一行请求就回一行固定的成功结果；stdin 关掉以后 touch 一个标记文件再退出
    private func echoScript(marker: URL) -> String {
        """
        while read line; do
          echo '\(PreviewFixtures.okReply)'
        done
        touch '\(marker.path)'
        """
    }

    @Test func 正常对话() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let marker = dir.url.appending(path: "closed")
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: echoScript(marker: marker))
        let s = PreviewSession(helper: fake)
        let o = try await s.open(userDir: dir.url, schema: "py")
        #expect(o.state.preedit == "ok")
        #expect(o.librimeVersion == "1.16.0")
        #expect(try await s.input("a").preedit == "ok")
        #expect(try await s.key(.pageDown).preedit == "ok")
        #expect(try await s.select(0).preedit == "ok")
        #expect(try await s.clear().preedit == "ok")
        await s.close()
        // close 关了 stdin，并且等脚本跑完才返回
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(.timeLimit(.minutes(1))) func 同时发的请求排队() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        // 回的 preedit 是第几个请求；回之前稍等一下，让别的请求有机会插进来
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: """
            n=0
            while read line; do
              n=$((n+1)); sleep 0.02
              echo "{\\"ok\\":true,\\"state\\":{\\"preedit\\":\\"$n\\",\\"cursor\\":0,\\"candidates\\":[],\\"pageNo\\":0,\\"isLastPage\\":true,\\"highlighted\\":0}}"
            done
            """)
        let s = PreviewSession(helper: fake)
        _ = try await s.open(userDir: dir.url, schema: "py")
        let got = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await s.input("a").preedit } }
            return try await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(got == Set((2...9).map(String.init)))
        await s.close()
    }

    @Test func 辅助程序回的错误() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: """
            while read line; do
              echo '{"ok":false,"error":{"kind":"schemaMissing","message":"m"}}'
            done
            """)
        let s = PreviewSession(helper: fake)
        await #expect(throws: PreviewError.failed(.schemaMissing, "m")) {
            try await s.open(userDir: dir.url, schema: "x")
        }
        // 辅助程序还活着，可以接着用
        await #expect(throws: PreviewError.failed(.schemaMissing, "m")) { try await s.input("a") }
        await s.close()
    }

    @Test func 超时就杀掉() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: "read line\nexec sleep 30")
        let s = PreviewSession(helper: fake, openTimeout: .milliseconds(300), requestTimeout: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: PreviewError.timedOut) {
            try await s.open(userDir: dir.url, schema: "py")
        }
        #expect(clock.now - start < .seconds(10))   // 卡住的话要等 30 秒；留够并行时的余量
        // 进程已经停了，之后的请求都报 helperDied
        try await expectHelperDied { _ = try await s.input("a") }
        await s.close()
    }

    @Test func 超时以后子进程拿着管道也不卡住() async throws {
        // sh 先 fork 一个 sleep 再等它（不是 exec）：杀掉 sh 以后 sleep 还拿着 stdout，
        // 读不到 EOF。会话不能因此卡住
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: "read line\nsleep 30")
        let s = PreviewSession(helper: fake, openTimeout: .milliseconds(300), requestTimeout: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: PreviewError.timedOut) {
            try await s.open(userDir: dir.url, schema: "py")
        }
        await s.close()
        // 卡住的话要等 sleep 30 结束；10 秒的上限留够了测试并行时的余量
        #expect(clock.now - start < .seconds(10))
    }

    @Test func 中途退出() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: """
            echo "WARNING: Logging before InitGoogleLogging() is written to STDERR" >&2
            echo "I20261016 11:16:31.6 x] info" >&2
            echo "真正的错" >&2
            exit 3
            """)
        let s = PreviewSession(helper: fake)
        await #expect(throws: PreviewError.helperDied(status: 3, stderr: ["真正的错"])) {
            try await s.open(userDir: dir.url, schema: "py")
        }
        await #expect(throws: PreviewError.helperDied(status: 3, stderr: ["真正的错"])) {
            try await s.input("a")
        }
        await s.close()
    }

    @Test func 回答以后再退出() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: """
            read line
            echo '\(PreviewFixtures.okReply)'
            read line
            echo "坏了" >&2
            exit 5
            """)
        let s = PreviewSession(helper: fake)
        _ = try await s.open(userDir: dir.url, schema: "py")
        await #expect(throws: PreviewError.helperDied(status: 5, stderr: ["坏了"])) { try await s.input("a") }
        await s.close()
    }

    @Test func 乱码输出() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: "read line\necho garbage\nexec sleep 30")
        let s = PreviewSession(helper: fake)
        let clock = ContinuousClock()
        let start = clock.now
        try await expectHelperDied { _ = try await s.open(userDir: dir.url, schema: "py") }
        #expect(clock.now - start < .seconds(10))   // 卡住的话要等 30 秒；留够并行时的余量
        await s.close()
    }

    @Test func 成功但没有状态也算乱码() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: """
            while read line; do echo '{"ok":true}'; done
            """)
        let s = PreviewSession(helper: fake)
        try await expectHelperDied { _ = try await s.open(userDir: dir.url, schema: "py") }
        await s.close()
    }

    @Test func 拒绝真实目录不启动进程() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let marker = dir.url.appending(path: "started")
        let fake = try PreviewFixtures.fakeHelper(in: dir.url, script: """
            touch '\(marker.path)'
            while read line; do echo '\(PreviewFixtures.okReply)'; done
            """)
        let s = PreviewSession(helper: fake)
        let real = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Rime")
        await #expect(throws: PreviewError.refusedDirectory) { try await s.open(userDir: real, schema: "py") }
        await #expect(throws: PreviewError.refusedDirectory) {
            try await s.open(userDir: real.appending(path: "build"), schema: "py")
        }
        await s.close()
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func 找不到辅助程序() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = PreviewSession(helper: dir.url.appending(path: "no-such-helper"))
        await #expect(throws: PreviewError.helperMissing) { try await s.open(userDir: dir.url, schema: "py") }
        await #expect(throws: PreviewError.helperMissing) { try await s.input("a") }
        await s.close()
    }

    @Test func stderr过滤() {
        #expect(PreviewSession.filterStderr(
            "WARNING: Logging before InitGoogleLogging() is written to STDERR\nI20261016 11:16:31.607891 0x1 modules.cc:96] x\n坏了"
        ) == ["坏了"])
        #expect(PreviewSession.filterStderr("W20261016 11:16:31.607891 0x1 a.cc:1] w\nE20261016 11:16:31.6 0x1 a.cc:1] e\n\n") ==
                ["E20261016 11:16:31.6 0x1 a.cc:1] e"])
        let many = (1...15).map { "第\($0)行" }.joined(separator: "\n")
        #expect(PreviewSession.filterStderr(many) == (6...15).map { "第\($0)行" })
    }

    @Test func 出错说明() {
        #expect(PreviewError.timedOut.description.contains("太久"))
        #expect(PreviewError.helperDied(status: 3, stderr: ["a", "真正的错"]).description.contains("真正的错"))
        #expect(PreviewError.packagesNotCached(["rime-ice"]).description.contains("rime-ice"))
    }

    @Test func 找辅助程序() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let app = dir.url.appending(path: "X.app", directoryHint: .isDirectory)
        let helpers = app.appending(path: "Contents/Helpers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let helper = try PreviewFixtures.fakeHelper(in: helpers, script: "exit 0")
        let named = helpers.appending(path: "rime-preview-helper")
        try FileManager.default.moveItem(at: helper, to: named)
        let bundle = try #require(Bundle(url: app))
        #expect(PreviewHelperLocator.locate(bundle: bundle)?.standardizedFileURL.path == named.standardizedFileURL.path)
    }

    @Test func 在可执行文件旁边找辅助程序() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let app = dir.url.appending(path: "Y.app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleExecutable": "Y", "CFBundleIdentifier": "test.y-\(UUID().uuidString)"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        let exe = try PreviewFixtures.fakeHelper(in: macOS, script: "exit 0")
        try FileManager.default.moveItem(at: exe, to: macOS.appending(path: "Y"))
        let helper = try PreviewFixtures.fakeHelper(in: macOS, script: "exit 0")
        let named = macOS.appending(path: "rime-preview-helper")
        try FileManager.default.moveItem(at: helper, to: named)
        let bundle = try #require(Bundle(url: app))
        #expect(PreviewHelperLocator.locate(bundle: bundle)?.standardizedFileURL.path == named.standardizedFileURL.path)

        // 都没有就是 nil
        try FileManager.default.removeItem(at: named)
        #expect(PreviewHelperLocator.locate(bundle: bundle) == nil)
    }

    private func expectHelperDied(_ body: () async throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        do {
            try await body()
            Issue.record("应该抛 helperDied", sourceLocation: sourceLocation)
        } catch let error as PreviewError {
            guard case .helperDied = error else {
                Issue.record("应该是 helperDied，实际是 \(error)", sourceLocation: sourceLocation)
                return
            }
        }
    }
}

/// 真的辅助程序 + 编译好的临时配置。没装鼠须管时跳过
@Suite(.enabled(if: RimeTools.installed))
struct PreviewSessionHelperTests {
    @Test func 真的辅助程序出候选() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = try PreviewFixtures.compiledConfig(in: dir.url)
        let s = PreviewSession(helper: PreviewFixtures.helper)
        let o = try await s.open(userDir: rime, schema: "py")
        #expect(o.librimeVersion.hasPrefix("1."))
        let state = try await s.input("nihao")
        #expect(state.candidates.first?.text == "你好", "\(state)")
        #expect(try await s.clear().candidates.isEmpty)
        await s.close()
    }
}
