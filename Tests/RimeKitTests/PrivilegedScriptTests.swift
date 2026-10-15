import Foundation
import Testing
@testable import RimeKit

/// 提权后运行的那段脚本：在 root 自己的临时目录里重新核对，再安装那份副本。
/// 测试里用普通用户运行，把 installer 换成 /usr/bin/true。
@Suite struct PrivilegedScriptTests {
    func run(_ pkg: URL, sha256: String?) throws -> ShellResult {
        try Shell.run("/bin/sh", ["-c", PrivilegedInstallScript.script(installer: "/usr/bin/true"), "sh",
                                  pkg.path, sha256 ?? "", SquirrelPackageVerifier.teamID])
    }

    @Test func sha256对不上就不装() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = dir.url.appending(path: "Squirrel.pkg")
        try Data("swapped".utf8).write(to: pkg)
        let r = try run(pkg, sha256: Hashing.sha256(of: Data("original".utf8)))
        #expect(r.status == PrivilegedInstallScript.checksumMismatch)
    }

    @Test func 签名检查不过就不装() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = dir.url.appending(path: "Squirrel.pkg")
        try Data("not a pkg".utf8).write(to: pkg)
        let r = try run(pkg, sha256: Hashing.sha256(of: Data("not a pkg".utf8)))
        #expect(r.status == PrivilegedInstallScript.signatureInvalid)
    }

    /// 去掉「管理员权限」后用 osascript 真跑：路径里的空格、引号和脚本里的换行都要原样交给 shell，退出码要原样传回
    @Test func 授权框的脚本能真的跑起来() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let sub = dir.url.appending(path: "a \"b\" 'c'")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let pkg = sub.appending(path: "S.pkg")
        try Data("not a pkg".utf8).write(to: pkg)
        let script = AuthorizationPromptInstaller.appleScript(for: pkg, sha256: Hashing.sha256(of: Data("not a pkg".utf8)))
            .replacingOccurrences(of: " with administrator privileges", with: "")
        let r = try Shell.run("/usr/bin/osascript", ["-e", script])
        #expect(r.status != 0)
        #expect(r.stderr.contains("(\(PrivilegedInstallScript.signatureInvalid))"))
    }

    @Test func 退出码翻译成中文错误() {
        #expect(PrivilegedInstallScript.error(status: PrivilegedInstallScript.checksumMismatch, message: "")
                == InstallError.recheckFailed("安装前再次核对时，安装包的 sha256 变了（可能被替换），没有安装"))
        #expect(PrivilegedInstallScript.error(status: 1, message: "installer: boom") == InstallError.installerFailed("installer: boom"))
    }

    @Test func 授权框的脚本把参数都加了引号() {
        let s = AuthorizationPromptInstaller.appleScript(for: URL(fileURLWithPath: "/tmp/a \"b\"/S.pkg"), sha256: "abc")
        #expect(s.hasPrefix(#"do shell script "/bin/sh -c " & quoted form of ""#))
        #expect(s.contains(#"& " sh " & quoted form of "/tmp/a \"b\"/S.pkg" & " " & quoted form of "abc" & " " & quoted form of "28HU5A7B46" with administrator privileges"#))
    }
}
