import Foundation

/// 命令行输出：正常运行时打印到终端，测试时收集起来检查
final class Output: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let echo: Bool

    init(echo: Bool) {
        self.echo = echo
    }

    func line(_ s: String) {
        lock.withLock { lines.append(s) }
        if echo { print(s) }
    }

    func error(_ s: String) {
        lock.withLock { lines.append(s) }
        if echo { FileHandle.standardError.write(Data((s + "\n").utf8)) }
    }

    var text: String {
        lock.withLock { lines.joined(separator: "\n") }
    }
}
