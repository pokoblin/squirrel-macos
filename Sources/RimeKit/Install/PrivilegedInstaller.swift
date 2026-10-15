import Foundation

public enum InstallError: Error, Equatable, Sendable, CustomStringConvertible {
    case cancelled
    case sudoUnavailable
    case installerFailed(String)
    case recheckFailed(String)
    case versionMismatch(expected: String, found: String?)

    public var description: String {
        switch self {
        case .cancelled:
            return "你取消了授权，鼠须管没有安装"
        case .sudoUnavailable:
            return "需要管理员权限才能安装鼠须管：命令行里请先配置免密 sudo，或者加 --gui-auth 弹出系统授权框"
        case .installerFailed(let message):
            return "安装鼠须管失败：\(message)"
        case .recheckFailed(let message):
            return message
        case let .versionMismatch(expected, found):
            return "装完后鼠须管的版本是 \(found ?? "（找不到）")，不是预期的 \(expected)"
        }
    }
}

/// 用管理员权限安装。实现必须在提权以后重新核对安装包再装（见 PrivilegedInstallScript）。
public protocol PrivilegedInstalling: Sendable {
    func installPackage(_ pkg: URL, sha256: String?) async throws
}

/// 提权后运行的脚本。安装包原来放在用户自己能写的暂存目录里，检查完到 root 的 installer 打开它之间，
/// 同一个用户的其它程序可以把它换掉。所以提权后先复制到只有 root 能写的临时目录，
/// 在这份副本上重新核对 sha256、签名和团队 ID，再安装这份副本。
/// 参数：$1 安装包路径，$2 期望的 sha256（可以为空），$3 团队 ID。
public enum PrivilegedInstallScript {
    public static let checksumMismatch: Int32 = 90
    public static let signatureInvalid: Int32 = 91
    public static let wrongTeam: Int32 = 92
    public static let copyFailed: Int32 = 93

    public static func script(installer: String = "/usr/sbin/installer") -> String {
        #"""
        set -u
        src="$1"; want="$2"; team="$3"
        d=$(/usr/bin/mktemp -d /private/var/tmp/squirrel-macos.XXXXXX) || exit 93
        trap '/bin/rm -rf "$d"' EXIT
        pkg="$d/Squirrel.pkg"
        /bin/cp "$src" "$pkg" || exit 93
        if [ -n "$want" ]; then
          got=$(/usr/bin/openssl dgst -sha256 -r "$pkg" | /usr/bin/cut -d " " -f 1)
          [ "$got" = "$want" ] || exit 90
        fi
        out=$(/usr/sbin/pkgutil --check-signature "$pkg" 2>&1) || exit 91
        printf "%s\n" "$out" | /usr/bin/grep -q "Notarization: trusted by the Apple notary service" || exit 91
        printf "%s\n" "$out" | /usr/bin/grep -q "1\. Developer ID Installer: .*($team)" || exit 92
        "\#(installer)" -pkg "$pkg" -target /
        """#
    }

    /// 把脚本的退出码翻译成错误
    public static func error(status: Int32, message: String) -> InstallError {
        switch status {
        case checksumMismatch: return .recheckFailed("安装前再次核对时，安装包的 sha256 变了（可能被替换），没有安装")
        case signatureInvalid: return .recheckFailed("安装前再次核对时，安装包的签名或公证不对（可能被替换），没有安装")
        case wrongTeam: return .recheckFailed("安装前再次核对时，安装包不是鼠须管作者签名的（可能被替换），没有安装")
        case copyFailed: return .recheckFailed("安装前复制安装包到安全目录失败，没有安装")
        default: return .installerFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// 免密 sudo（测试机里的 rimectl 用）
public struct SudoPackageInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL, sha256: String?) async throws {
        let r = try Shell.run("/usr/bin/sudo", ["-n", "/bin/sh", "-c", PrivilegedInstallScript.script(), "sh",
                                                pkg.path, sha256 ?? "", SquirrelPackageVerifier.teamID])
        guard r.status == 0 else {
            if r.stderr.contains("password is required") { throw InstallError.sudoUnavailable }
            throw PrivilegedInstallScript.error(status: r.status, message: r.stderr + r.stdout)
        }
    }
}

/// 弹出系统授权框，用户输一次密码（应用里用；测试机里 rimectl --gui-auth 也可以用）
public struct AuthorizationPromptInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL, sha256: String?) async throws {
        let source = Self.appleScript(for: pkg, sha256: sha256)
        try await MainActor.run {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.executeAndReturnError(&error) != nil else {
                let code = error?[NSAppleScript.errorNumber] as? Int
                if code == -128 { throw InstallError.cancelled }   // 用户点了取消
                let message = (error?[NSAppleScript.errorMessage] as? String) ?? "未知错误 \(code ?? 0)"
                // do shell script 失败时，错误号就是脚本的退出码
                throw PrivilegedInstallScript.error(status: Int32(code ?? 1), message: message)
            }
        }
    }

    /// 每个参数都用 AppleScript 的 quoted form of 交给 shell，避免空格、引号出问题
    static func appleScript(for pkg: URL, sha256: String?) -> String {
        func literal(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let parts = [PrivilegedInstallScript.script(), pkg.path, sha256 ?? "", SquirrelPackageVerifier.teamID]
        let script = literal(parts[0]).replacingOccurrences(of: "\n", with: "\\n")
        return #"do shell script "/bin/sh -c " & quoted form of "#
            + script
            + #" & " sh " & quoted form of "# + literal(parts[1])
            + #" & " " & quoted form of "# + literal(parts[2])
            + #" & " " & quoted form of "# + literal(parts[3])
            + " with administrator privileges"
    }
}
