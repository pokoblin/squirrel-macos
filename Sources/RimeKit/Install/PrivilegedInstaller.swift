import Foundation

public enum InstallError: Error, Equatable, Sendable, CustomStringConvertible {
    case cancelled
    case sudoUnavailable
    case installerFailed(String)
    case versionMismatch(expected: String, found: String?)

    public var description: String {
        switch self {
        case .cancelled:
            return "你取消了授权，鼠须管没有安装"
        case .sudoUnavailable:
            return "需要管理员权限才能安装鼠须管：命令行里请先配置免密 sudo，或者加 --gui-auth 弹出系统授权框"
        case .installerFailed(let message):
            return "安装鼠须管失败：\(message)"
        case let .versionMismatch(expected, found):
            return "装完后鼠须管的版本是 \(found ?? "（找不到）")，不是预期的 \(expected)"
        }
    }
}

/// 用管理员权限运行 installer
public protocol PrivilegedInstalling: Sendable {
    func installPackage(_ pkg: URL) async throws
}

/// 免密 sudo（测试机里的 rimectl 用）
public struct SudoPackageInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL) async throws {
        let r = try Shell.run("/usr/bin/sudo", ["-n", "/usr/sbin/installer", "-pkg", pkg.path, "-target", "/"])
        guard r.status == 0 else {
            if r.stderr.contains("password is required") { throw InstallError.sudoUnavailable }
            throw InstallError.installerFailed((r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// 弹出系统授权框，用户输一次密码（应用里用；测试机里 rimectl --gui-auth 也可以用）
public struct AuthorizationPromptInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL) async throws {
        let source = Self.appleScript(for: pkg)
        try await MainActor.run {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.executeAndReturnError(&error) != nil else {
                let code = error?[NSAppleScript.errorNumber] as? Int
                if code == -128 { throw InstallError.cancelled }   // 用户点了取消
                throw InstallError.installerFailed((error?[NSAppleScript.errorMessage] as? String) ?? "未知错误 \(code ?? 0)")
            }
        }
    }

    /// 路径用 AppleScript 的 quoted form of 交给 shell，避免空格、引号出问题
    static func appleScript(for pkg: URL) -> String {
        let escaped = pkg.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"do shell script "/usr/sbin/installer -pkg " & quoted form of "\#(escaped)" & " -target /" with administrator privileges"#
    }
}
