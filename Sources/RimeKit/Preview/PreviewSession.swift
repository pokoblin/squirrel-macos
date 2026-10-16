import Darwin
import Foundation
import Synchronization

/// 试打用的输入法引擎。PreviewSession 是真的（和辅助程序对话），测试时可以换成假的
public protocol PreviewEngine: Sendable {
    func open(userDir: URL, schema: String) async throws -> PreviewOpened
    func input(_ text: String) async throws -> PreviewState
    func key(_ key: PreviewKey) async throws -> PreviewState
    func select(_ index: Int) async throws -> PreviewState
    func clear() async throws -> PreviewState
    func close() async
}

/// open 的结果：librime 的版本和刚打开时的样子
public struct PreviewOpened: Sendable, Equatable {
    public var librimeVersion: String
    public var state: PreviewState

    public init(librimeVersion: String, state: PreviewState) {
        self.librimeVersion = librimeVersion
        self.state = state
    }
}

public enum PreviewError: Error, Equatable, CustomStringConvertible {
    /// 找不到辅助程序，或者启动不了
    case helperMissing
    /// 要在真实的 ~/Library/Rime 上试打，拒绝了
    case refusedDirectory
    /// 辅助程序回了错误（它自己还活着）
    case failed(PreviewFailureKind, String)
    /// 辅助程序太久没回，已经杀掉
    case timedOut
    /// 辅助程序退出、崩溃，或者回了看不懂的内容。status 是退出码（被信号杀掉时是 nil），stderr 是过滤后的最后几行
    case helperDied(status: Int32?, stderr: [String])
    /// 鼠须管还没部署过，没有「当前生效」的配置
    case notDeployed
    /// 「应用后的样子」要用的方案包还没下载
    case packagesNotCached([String])
    /// 编译副本失败（rime_deployer 的输出）
    case compileFailed([String])
    /// 副本里没有可以试打的方案
    case noSchemas

    public var description: String {
        switch self {
        case .helperMissing:
            return "找不到试打用的辅助程序 rime-preview-helper。"
        case .refusedDirectory:
            return "不能在真实的 ~/Library/Rime 上试打，只能用副本。"
        case let .failed(kind, message):
            let what: String = switch kind {
            case .loadFailed: "加载不了鼠须管的 librime"
            case .unsupportedVersion: "鼠须管的 librime 版本不支持"
            case .refusedDirectory: "辅助程序拒绝在真实的 ~/Library/Rime 上试打"
            case .schemaMissing: "副本里没有这个方案的编译结果"
            case .notOpen: "还没打开方案"
            case .badRequest: "辅助程序看不懂这个请求"
            }
            return message.isEmpty ? "\(what)。" : "\(what)：\(message)"
        case .timedOut:
            return "辅助程序太久没回应，已经停掉了。"
        case let .helperDied(status, stderr):
            let code = status.map { "（退出码 \($0)）" } ?? ""
            let last = stderr.last.map { "：\($0)" } ?? "。"
            return "辅助程序意外退出了\(code)\(last)"
        case .notDeployed:
            return "鼠须管还没部署过，没有可以试打的配置。"
        case let .packagesNotCached(ids):
            return "这些方案包还没下载：\(ids.joined(separator: "、"))。"
        case let .compileFailed(lines):
            let last = lines.last.map { "：\($0)" } ?? "。"
            return "编译试打用的配置失败了\(last)"
        case .noSchemas:
            return "配置里没有可以试打的方案。"
        }
    }
}

/// 找辅助程序：应用里在 Contents/Helpers/，rimectl 和测试在自己的可执行文件旁边（.build/debug/）
public enum PreviewHelperLocator {
    static let name = "rime-preview-helper"

    public static func locate(bundle: Bundle = .main) -> URL? {
        let fm = FileManager.default
        let inApp = bundle.bundleURL.appending(path: "Contents/Helpers/\(name)")
        if fm.isExecutableFile(atPath: inApp.path) { return inApp }
        if let executable = bundle.executableURL?.resolvingSymlinksInPath() {
            let beside = executable.deletingLastPathComponent().appending(path: name)
            if fm.isExecutableFile(atPath: beside.path) { return beside }
        }
        return nil
    }
}

/// 和辅助程序（rime-preview-helper）对话。第一次请求时才启动它；一次只发一个请求，同时来的排队。
/// 辅助程序退出、崩溃、超时以后，这个会话之后的请求都报 helperDied，要重试就新建一个会话。
public actor PreviewSession: PreviewEngine {
    private let helper: URL
    private let squirrelApp: URL?
    private let openTimeout: Duration
    private let requestTimeout: Duration

    private var running: Running?
    /// 进程停了以后，之后的请求都抛这个
    private var dead: PreviewError?
    /// 排队：正在发请求时，后来的在这里等
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// 正在运行的辅助程序和它的管道
    private struct Running {
        let process: Process
        let stdin: FileHandle
        let stdout: FileHandle
        /// stdout 读到的数据块，结束（EOF）时 finish
        let chunks: Mailbox<Data>
        /// 进程退出时放进退出码（被信号杀掉时是 nil）
        let exit: Mailbox<Int32?>
        /// stderr 写进一个已经删掉的临时文件：不会因为管道写满卡住辅助程序，用完也不留文件
        let stderr: FileHandle
        /// stdout 里还没凑成一行的部分
        var pending = Data()
    }

    public init(helper: URL, squirrelApp: URL? = nil,
                openTimeout: Duration = .seconds(15), requestTimeout: Duration = .seconds(5)) {
        self.helper = helper
        self.squirrelApp = squirrelApp
        self.openTimeout = openTimeout
        self.requestTimeout = requestTimeout
    }

    deinit {
        if let running, running.process.isRunning { running.process.terminate() }
    }

    public func open(userDir: URL, schema: String) async throws -> PreviewOpened {
        // 第一道保险：真实的 ~/Library/Rime 连进程都不启动（辅助程序里还会再查一次）
        if RimeDirectoryGuard.isInsideRealRimeDirectory(userDir) { throw PreviewError.refusedDirectory }
        let response = try await send(.open(userDir: userDir.path, schema: schema), timeout: openTimeout)
        return PreviewOpened(librimeVersion: response.librimeVersion ?? "", state: response.state ?? .empty)
    }

    public func input(_ text: String) async throws -> PreviewState {
        try await send(.input(text), timeout: requestTimeout).state ?? .empty
    }

    public func key(_ key: PreviewKey) async throws -> PreviewState {
        try await send(.key(key), timeout: requestTimeout).state ?? .empty
    }

    public func select(_ index: Int) async throws -> PreviewState {
        try await send(.select(index), timeout: requestTimeout).state ?? .empty
    }

    public func clear() async throws -> PreviewState {
        try await send(.clear, timeout: requestTimeout).state ?? .empty
    }

    /// 关掉辅助程序的 stdin，等它自己收尾退出；等太久就杀掉
    public func close() async {
        await acquire()
        defer { release() }
        guard running != nil else { return }
        let status = await stop(grace: requestTimeout)
        running = nil
        if dead == nil { dead = .helperDied(status: status, stderr: []) }
    }

    /// 去掉 glog 的 I/W 行和「WARNING: Logging before InitGoogleLogging()」、空行，留最后 10 行
    public static func filterStderr(_ text: String) -> [String] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if line.hasPrefix("WARNING: Logging before InitGoogleLogging()") { return false }
            if let first = line.first, first == "I" || first == "W" {
                let digits = line.dropFirst().prefix(8)
                if digits.count == 8 && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber) { return false }
            }
            return true
        }
        return Array(lines.suffix(10))
    }

    // MARK: - 发请求

    /// 发一个请求、读回一行结果。辅助程序回的错误转成 .failed，看不懂的内容当作辅助程序坏了
    private func send(_ request: PreviewRequest, timeout: Duration) async throws -> PreviewResponse {
        await acquire()
        defer { release() }
        if let dead { throw dead }
        try start()

        do {
            try running?.stdin.write(contentsOf: PreviewLine.encode(request))
        } catch {
            // 写不进去：辅助程序已经退出了
            throw await died(kill: false)
        }

        let line: String
        switch await readLine(timeout: timeout) {
        case let .line(text):
            line = text
        case .eof:
            throw await died(kill: false)
        case .timedOut:
            _ = await died(kill: true)
            throw PreviewError.timedOut
        }

        guard let response = try? PreviewLine.decode(PreviewResponse.self, from: line) else {
            throw await died(kill: true)
        }
        if response.ok {
            guard response.state != nil else { throw await died(kill: true) }
            return response
        }
        guard let failure = response.error else { throw await died(kill: true) }
        throw PreviewError.failed(failure.kind, failure.message)
    }

    /// 还没启动就启动辅助程序
    private func start() throws {
        guard running == nil else { return }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw PreviewError.helperMissing }

        let process = Process()
        process.executableURL = helper
        process.arguments = squirrelApp.map { ["--squirrel", $0.path] } ?? []
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        let stderrWrite: FileHandle
        let stderrRead: FileHandle
        do {
            let file = FileManager.default.temporaryDirectory.appending(path: "rime-preview-stderr-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw PreviewError.helperMissing }
            defer { try? FileManager.default.removeItem(at: file) }
            stderrWrite = try FileHandle(forWritingTo: file)
            stderrRead = try FileHandle(forReadingFrom: file)
        } catch {
            throw PreviewError.helperMissing
        }
        process.standardError = stderrWrite
        // 辅助程序先退出时，往它的 stdin 写只报错，不让 SIGPIPE 把我们杀掉
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let chunks = Mailbox<Data>()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                chunks.finish()
            } else {
                chunks.put(data)
            }
        }
        let exit = Mailbox<Int32?>()
        process.terminationHandler = { process in
            exit.put(process.terminationReason == .exit ? process.terminationStatus : nil)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            throw PreviewError.helperMissing
        }
        // 写的那头辅助程序已经有了，我们这边的关掉
        try? stderrWrite.close()
        running = Running(process: process, stdin: stdinPipe.fileHandleForWriting,
                          stdout: stdoutPipe.fileHandleForReading,
                          chunks: chunks, exit: exit, stderr: stderrRead)
    }

    private enum ReadResult {
        case line(String), eof, timedOut
    }

    /// 读一行 stdout；超过 timeout 还没读到就算超时
    private func readLine(timeout: Duration) async -> ReadResult {
        let deadline = ContinuousClock.now + timeout
        while var current = running {
            if let newline = current.pending.firstIndex(of: 0x0a) {
                let line = current.pending[current.pending.startIndex..<newline]
                current.pending.removeSubrange(current.pending.startIndex...newline)
                running = current
                return .line(String(decoding: line, as: UTF8.self))
            }
            switch await current.chunks.next(timeout: deadline - .now) {
            case let .value(data): running?.pending.append(data)
            case .finished: return .eof
            case .timedOut: return .timedOut
            }
        }
        return .eof
    }

    // MARK: - 进程停了

    /// 停掉辅助程序（kill 为 true 时马上杀掉，不然先等它自己退出），记下 helperDied 并返回
    private func died(kill: Bool) async -> PreviewError {
        let status = await stop(grace: kill ? .zero : .seconds(2))
        let error = PreviewError.helperDied(status: status, stderr: Self.filterStderr(stderrTail()))
        dead = error
        running = nil
        return error
    }

    /// 等进程退出，最多等 grace；再不退出就 SIGTERM，还不退出就 SIGKILL。返回退出码
    private func stop(grace: Duration) async -> Int32? {
        guard let running else { return nil }
        running.stdout.readabilityHandler = nil
        try? running.stdin.close()

        if grace > .zero, case let .value(status) = await running.exit.next(timeout: grace) { return status }
        if running.process.isRunning { running.process.terminate() }
        if case let .value(status) = await running.exit.next(timeout: .seconds(2)) { return status }
        if running.process.isRunning { Darwin.kill(running.process.processIdentifier, SIGKILL) }
        if case let .value(status) = await running.exit.next(timeout: .seconds(2)) { return status }
        return nil
    }

    /// stderr 最后 32KB（不从一行中间开始）
    private func stderrTail() -> String {
        guard let handle = running?.stderr, let end = try? handle.seekToEnd() else { return "" }
        let limit: UInt64 = 32 * 1024
        let start = end > limit ? end - limit : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return "" }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        return text
    }

    // MARK: - 排队

    private func acquire() async {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
    }

    /// 让下一个排队的接着用（busy 保持 true），没人排队就空闲
    private func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// 一个线程安全的小信箱：别的线程往里放东西，一个等待者带超时地取。
/// 超时用一个 sleep 的小任务，取到东西就取消它，不会留下后台任务或没恢复的 continuation
final class Mailbox<Value: Sendable>: Sendable {
    enum Next: Sendable {
        case value(Value), finished, timedOut
    }

    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Next, Never>
    }

    private struct State {
        var values: [Value] = []
        var finished = false
        var waiter: Waiter?
        var nextID: UInt64 = 0
        /// 这个编号以前（含）的等待都已经超时
        var expiredUpTo: UInt64 = 0
    }

    private let state = Mutex(State())

    func put(_ value: Value) {
        let waiter = state.withLock { s -> Waiter? in
            if let w = s.waiter {
                s.waiter = nil
                return w
            }
            s.values.append(value)
            return nil
        }
        waiter?.continuation.resume(returning: .value(value))
    }

    func finish() {
        let waiter = state.withLock { s -> Waiter? in
            s.finished = true
            defer { s.waiter = nil }
            return s.waiter
        }
        waiter?.continuation.resume(returning: .finished)
    }

    /// 取一个东西：有就马上返回；结束了返回 .finished；等超过 timeout 返回 .timedOut。同一时间只能有一个等待者
    func next(timeout: Duration) async -> Next {
        let id = state.withLock { s in
            s.nextID += 1
            return s.nextID
        }
        let timer = Task { [self] in
            do {
                try await Task.sleep(for: max(timeout, .zero))
                expire(id)
            } catch {}
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            var displaced: Waiter?
            let ready = state.withLock { s -> Next? in
                if !s.values.isEmpty { return .value(s.values.removeFirst()) }
                if s.finished { return .finished }
                if id <= s.expiredUpTo { return .timedOut }
                // 本不该有两个等待者；万一有，先来的那个当作超时，不让它永远等下去
                displaced = s.waiter
                s.waiter = Waiter(id: id, continuation: continuation)
                return nil
            }
            displaced?.continuation.resume(returning: .timedOut)
            if let ready { continuation.resume(returning: ready) }
        }
    }

    private func expire(_ id: UInt64) {
        let waiter = state.withLock { s -> Waiter? in
            s.expiredUpTo = max(s.expiredUpTo, id)
            guard let w = s.waiter, w.id == id else { return nil }
            s.waiter = nil
            return w
        }
        waiter?.continuation.resume(returning: .timedOut)
    }
}
