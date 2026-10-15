import Foundation
import Testing
@testable import RimeKit

@Suite struct OsascriptInstallerTests {
    @Test func 用户点了取消() {
        #expect(OsascriptPrivilegedInstaller.error(stderr: "0:139: execution error: User canceled. (-128)\n") == .cancelled)
    }

    @Test func 脚本的退出码翻译成中文错误() {
        #expect(OsascriptPrivilegedInstaller.error(stderr: "0:300: execution error:  (90)")
                == PrivilegedInstallScript.error(status: PrivilegedInstallScript.checksumMismatch, message: ""))
        #expect(OsascriptPrivilegedInstaller.error(stderr: "0:300: execution error: installer: boom (1)")
                == .installerFailed("0:300: execution error: installer: boom (1)"))
    }

    @Test func 认不出的错误原样报出来() {
        #expect(OsascriptPrivilegedInstaller.error(stderr: "something odd") == .installerFailed("something odd"))
    }

    /// 去掉「管理员权限」后真的跑一遍 osascript：确认错误号能从 stderr 里读出来
    @Test func 真的跑osascript时能读出脚本的退出码() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = dir.url.appending(path: "S.pkg")
        try Data("not a pkg".utf8).write(to: pkg)
        let script = AuthorizationPromptInstaller.appleScript(for: pkg, sha256: Hashing.sha256(of: Data("not a pkg".utf8)))
            .replacingOccurrences(of: " with administrator privileges", with: "")
        let r = try Shell.run("/usr/bin/osascript", ["-e", script])
        #expect(r.status != 0)
        #expect(OsascriptPrivilegedInstaller.error(stderr: r.stderr)
                == PrivilegedInstallScript.error(status: PrivilegedInstallScript.signatureInvalid, message: ""))
    }
}
