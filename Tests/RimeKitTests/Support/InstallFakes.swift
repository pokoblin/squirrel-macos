import Foundation
@testable import RimeKit

enum InstallFixtures {
    static func pkgURL(_ version: String) -> URL {
        URL(string: "https://github.com/rime/squirrel/releases/download/\(version)/Squirrel-\(version).pkg")!
    }

    static func releaseJSON(version: String, digest: String?, assetName: String? = nil) -> Data {
        let name = assetName ?? "Squirrel-\(version).pkg"
        let digestField = digest.map { #","digest":"sha256:\#($0)""# } ?? ""
        return Data(#"""
        {"tag_name":"\#(version)","assets":[{"name":"\#(name)","browser_download_url":"\#(pkgURL(version).absoluteString)","size":1\#(digestField)}]}
        """#.utf8)
    }

    /// 在假的 Squirrel.app 里写 Info.plist，模拟装好了某个版本
    static func writeInfoPlist(app: URL, version: String) throws {
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleVersion": version, "CFBundleIdentifier": "im.rime.inputmethod.Squirrel"],
            format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
    }
}
/// 假的检查：可以设成抛错；记录收到的 sha256
final class FakeVerifier: PackageVerifying, @unchecked Sendable {
    private let lock = NSLock()
    private var checked: [String?] = []
    var error: VerificationError?

    func verify(_ pkg: URL, sha256: String?) throws {
        lock.withLock { checked.append(sha256) }
        if let error { throw error }
    }

    var checkedSHA256: [String?] { lock.withLock { checked } }
}

/// 假的提权安装：记录装过的包；设了 version 就往假的 Squirrel.app 写 Info.plist
final class FakePrivileged: PrivilegedInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private let app: URL
    private var packages: [String] = []
    var version: String?
    var error: InstallError?

    init(app: URL, version: String?) {
        self.app = app
        self.version = version
    }

    var installedPackages: [String] { lock.withLock { packages } }

    func installPackage(_ pkg: URL) async throws {
        try record(pkg)
    }

    private func record(_ pkg: URL) throws {
        lock.withLock { packages.append(pkg.lastPathComponent) }
        if let error { throw error }
        if let version { try InstallFixtures.writeInfoPlist(app: app, version: version) }
    }
}
/// 假的输入法服务
final class FakeInputSource: InputSourceControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var current: InputSourceState
    private var pumps = 0
    private var log: [String] = []
    /// 等了这么多次之后，变成用户已经添加好
    var enableAfterPumps: Int?
    var selectError: InputSourceError?

    init(_ state: InputSourceState) {
        current = state
    }

    var calls: [String] { lock.withLock { log } }
    var pumpCount: Int { lock.withLock { pumps } }

    func state() -> InputSourceState { lock.withLock { current } }

    func selectSquirrel() throws {
        try lock.withLock {
            log.append("select")
            if let selectError { throw selectError }
            current.selected = true
        }
    }

    func openKeyboardSettings() throws {
        lock.withLock { log.append("open") }
    }

    func pump(_ seconds: Double) async {
        recordPump()
    }

    private func recordPump() {
        lock.withLock {
            pumps += 1
            if let n = enableAfterPumps, pumps >= n { current.enabled = true }
        }
    }
}
