import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// 运行一个外部程序并等它结束（只用于系统自带的小工具，比如 ditto）
enum Shell {
    static func run(_ executable: String, _ arguments: [String]) throws -> ShellResult {
        let fm = FileManager.default
        // stderr 写到临时文件：如果和 stdout 都用管道、又先读完 stdout，
        // 程序往 stderr 写超过管道缓冲（约 64KB）时双方会互相等死
        let errFile = fm.temporaryDirectory.appending(path: "rimekit-stderr-\(UUID().uuidString)")
        guard fm.createFile(atPath: errFile.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: errFile.path])
        }
        defer { try? fm.removeItem(at: errFile) }
        let errHandle = try FileHandle(forWritingTo: errFile)
        defer { try? errHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = errHandle
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errData = (try? Data(contentsOf: errFile)) ?? Data()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }
}
