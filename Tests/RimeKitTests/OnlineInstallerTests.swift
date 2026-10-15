import Foundation
import Testing
@testable import RimeKit

/// 真的从 GitHub 取鼠须管安装包，做三道检查；再改 1 个字节，确认检查不过。只下载到临时目录，不安装。
/// RIMEKIT_ONLINE=1 swift test --filter OnlineInstallerTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1"))
struct OnlineInstallerTests {
    @Test func 真实安装包能通过检查改过的不能() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let release = try await SquirrelReleaseSource(http: URLSessionHTTPClient()).latest()
        #expect(release.sha256 != nil)
        let pkg = dir.url.appending(path: "Squirrel.pkg")
        try await URLSessionHTTPClient().download(release.downloadURL, to: pkg)
        try SquirrelPackageVerifier().verify(pkg, sha256: release.sha256)

        var bytes = try Data(contentsOf: pkg)
        bytes[1_000_000] ^= 0xFF
        let bad = dir.url.appending(path: "bad.pkg")
        try bytes.write(to: bad)
        #expect(throws: VerificationError.self) { try SquirrelPackageVerifier().verify(bad, sha256: release.sha256) }
        #expect(throws: VerificationError.self) { try SquirrelPackageVerifier().verify(bad, sha256: nil) }   // 不靠 sha256，pkgutil 也能发现
    }
}
