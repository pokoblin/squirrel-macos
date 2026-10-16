import Darwin
import Foundation
@testable import RimeKit

/// 试打预览的测试支持：编译好的测试配置、找辅助程序、和辅助程序对话的小客户端。
enum PreviewFixtures {
    /// swift test 编出来的辅助程序（测试 target 依赖它，所以一定先编好）
    static var helper: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // RimeKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根目录
            .appending(path: ".build/debug/rime-preview-helper")
    }

    /// 编码 yi 的 12 个单字，权重从 120 起每个减 10。每页 5 个，第 7 个「揖」在第 2 页第 2 个
    static let yiCharacters = ["一", "衣", "医", "依", "伊", "壹", "揖", "仪", "夷", "宜", "移", "遗"]

    /// 生成 py、wb 两个方案并编译，返回编译好的 Rime 用户目录（在 dir 里面）。
    /// pageSize：每页候选数，换目录的测试用不同的值区分两份配置
    static func compiledConfig(in dir: URL, pageSize: Int = 5) throws -> URL {
        let yi = yiCharacters.enumerated().map { "\($1)\tyi\t\(120 - $0 * 10)" }
        let pyDict = GenFixtures.dict("py", ["你\tni\t100", "好\thao\t100", "你好\tni hao\t1000"] + yi)
        let packages = try GenFixtures.makePackages(in: dir.appending(path: "cache"),
                                                    extra: ["pinyin": ["py.dict.yaml": pyDict]])
        var settings = Settings(schemas: ["py", "wb"])
        settings.appearance.pageSize = pageSize
        let out = dir.appending(path: "rime", directoryHint: .isDirectory)
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)
        let build = try RimeTools.build(out)
        guard build.status == 0 else { throw CompileFailed(stderr: build.stderr) }
        return out
    }

    struct CompileFailed: Error, CustomStringConvertible {
        let stderr: String
        var description: String { "测试配置编译失败：\(stderr)" }
    }
}

/// 和辅助程序对话的同步小客户端（只给测试用）。
/// stderr 写到临时文件（librime 的 glog 行不弄脏测试输出，需要时也能查）。
final class HelperProcess {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrFile: URL
    private var buffer = Data()
    private var inputClosed = false

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    init(helper: URL, arguments: [String] = []) throws {
        let fm = FileManager.default
        stderrFile = fm.temporaryDirectory.appending(path: "preview-helper-stderr-\(UUID().uuidString)")
        guard fm.createFile(atPath: stderrFile.path, contents: nil) else {
            throw Failure(description: "建不了 stderr 临时文件")
        }
        process.executableURL = helper
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = try FileHandle(forWritingTo: stderrFile)
        // 辅助程序先退出时，往它的 stdin 写只报错，不让 SIGPIPE 把测试进程杀掉
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
    }

    deinit {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: stderrFile)
    }

    func send(_ r: PreviewRequest) throws -> PreviewResponse {
        let line = try PreviewLine.encode(r)
        return try sendRaw(String(decoding: line.dropLast(), as: UTF8.self))
    }

    /// 原样发一行（不用带换行），读回一行结果
    func sendRaw(_ line: String) throws -> PreviewResponse {
        try stdinPipe.fileHandleForWriting.write(contentsOf: Data((line + "\n").utf8))
        let reply = try readLine(timeout: 15)
        return try PreviewLine.decode(PreviewResponse.self, from: reply)
    }

    /// 关掉 stdin，等辅助程序退出，返回退出码
    func closeInput() -> Int32 {
        if !inputClosed {
            inputClosed = true
            try? stdinPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// 辅助程序到目前为止写到 stderr 的内容
    func stderrText() -> String {
        String(decoding: (try? Data(contentsOf: stderrFile)) ?? Data(), as: UTF8.self)
    }

    /// 读一行；超时或者辅助程序退出了就报错，测试不会一直卡住
    private func readLine(timeout: TimeInterval) throws -> String {
        let fd = stdoutPipe.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let newline = buffer.firstIndex(of: 0x0a) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(decoding: line, as: UTF8.self)
            }
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, remaining)
            if ready == 0 { throw Failure(description: "等辅助程序回话超时。stderr：\(stderrText())") }
            if ready < 0 {
                if errno == EINTR { continue }
                throw Failure(description: "poll 失败：\(errno)")
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { throw Failure(description: "辅助程序关掉了 stdout。stderr：\(stderrText())") }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }
}
