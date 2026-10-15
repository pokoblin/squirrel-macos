import Foundation
@testable import RimeKit

/// 假的编译器：返回事先设置好的结果
struct FakeCompiler: RimeCompiler {
    var report = CompileReport(succeeded: true, errors: [])
    func compile(_ directory: URL) throws -> CompileReport { report }
}

/// 假的鼠须管：reload / launch 时往 Rime 目录写一个新的 user.yaml（模拟部署完成），
/// errorLine 不为空时同时往日志目录的 ERROR 文件追加一行
final class FakeSquirrel: SquirrelControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let locations: RimeLocations
    private var running: Bool
    private var buildTime = 1_000
    private var log: [String] = []
    var errorLine: String?

    init(locations: RimeLocations, running: Bool) {
        self.locations = locations
        self.running = running
    }

    var calls: [String] { lock.withLock { log } }

    func isRunning() -> Bool { lock.withLock { running } }

    func reload() throws {
        lock.withLock { log.append("reload") }
        try simulateDeploy()
    }

    func launch() throws {
        lock.withLock {
            log.append("launch")
            running = true
        }
        try simulateDeploy()
    }

    private func simulateDeploy() throws {
        let time = lock.withLock { () -> Int in
            buildTime += 1
            return buildTime
        }
        let fm = FileManager.default
        try fm.createDirectory(at: locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("var:\n  last_build_time: \(time)\n".utf8).write(to: locations.rimeDirectory.appending(path: "user.yaml"))
        if let errorLine {
            try fm.createDirectory(at: locations.logDirectory, withIntermediateDirectories: true)
            let file = locations.logDirectory.appending(path: "rime.squirrel.host.user.log.ERROR.20261015-000000.1")
            let old = (try? Data(contentsOf: file)) ?? Data()
            try (old + Data((errorLine + "\n").utf8)).write(to: file)
        }
    }
}

enum DeployFixtures {
    /// 临时的「鼠须管」（只有一个可执行的空 rime_deployer，让 squirrelInstalled 为真）、Rime 目录、日志目录
    static func locations(_ dir: TempDir) throws -> RimeLocations {
        let fm = FileManager.default
        let app = dir.url.appending(path: "Squirrel.app", directoryHint: .isDirectory)
        let deployer = app.appending(path: "Contents/MacOS/rime_deployer")
        try fm.createDirectory(at: deployer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: deployer)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deployer.path)
        return RimeLocations(
            rimeDirectory: dir.url.appending(path: "Rime", directoryHint: .isDirectory),
            squirrelApp: app,
            logDirectory: dir.url.appending(path: "logs", directoryHint: .isDirectory))
    }

    /// 不真的等待、很快超时的观察器
    static func watcher(_ locations: RimeLocations) -> DeployWatcher {
        DeployWatcher(locations: locations, pollInterval: .milliseconds(1), timeout: .milliseconds(20), sleep: { _ in })
    }
}
