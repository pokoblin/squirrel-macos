import Foundation

public enum VerificationError: Error, Equatable, Sendable, CustomStringConvertible {
    case checksumMismatch(expected: String, actual: String)
    case invalidPackage(String)
    case notDeveloperID
    case notNotarized
    case wrongTeam(String?)
    case gatekeeperRejected(String)

    public var description: String {
        switch self {
        case .checksumMismatch:
            return "下载的鼠须管安装包和 GitHub 上公布的校验值不一样（可能下载坏了或被改过），不安装"
        case .invalidPackage(let detail):
            return "鼠须管安装包坏了或被改过，不安装（\(detail)）"
        case .notDeveloperID:
            return "鼠须管安装包不是用苹果签发的开发者证书签名的，不安装"
        case .notNotarized:
            return "鼠须管安装包没有经过苹果公证，不安装"
        case .wrongTeam(let found):
            return "鼠须管安装包不是鼠须管作者签名的（\(found ?? "找不到签名者")），不安装"
        case .gatekeeperRejected(let detail):
            return "系统安全检查（Gatekeeper）拒绝了鼠须管安装包，不安装（\(detail)）"
        }
    }
}

public protocol PackageVerifying: Sendable {
    func verify(_ pkg: URL, sha256: String?) throws
}

/// 鼠须管安装包的三道检查（只改了 1 个字节的包 spctl 也会说 accepted，所以三道都要）
public struct SquirrelPackageVerifier: PackageVerifying {
    public static let teamID = "28HU5A7B46"

    public init() {}

    public func verify(_ pkg: URL, sha256: String?) throws {
        if let sha256 {
            let actual = try Hashing.sha256(of: pkg)
            guard actual == sha256.lowercased() else {
                throw VerificationError.checksumMismatch(expected: sha256.lowercased(), actual: actual)
            }
        }
        let p = try Shell.run("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
        try Self.checkPkgutil(status: p.status, output: p.stdout + p.stderr)
        let s = try Shell.run("/usr/sbin/spctl", ["-a", "-vv", "-t", "install", pkg.path])
        try Self.checkSpctl(status: s.status, output: s.stdout + s.stderr)
    }

    static func checkPkgutil(status: Int32, output: String) throws {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard status == 0 else {
            throw VerificationError.invalidPackage(lines.first { $0.hasPrefix("Status:") } ?? lines.joined(separator: " "))
        }
        guard lines.contains("Status: signed by a developer certificate issued by Apple for distribution") else {
            throw VerificationError.notDeveloperID
        }
        guard lines.contains("Notarization: trusted by the Apple notary service") else {
            throw VerificationError.notNotarized
        }
        let leaf = lines.first { $0.hasPrefix("1. ") }
        guard let leaf, leaf.contains("Developer ID Installer:"), leaf.hasSuffix("(\(teamID))") else {
            throw VerificationError.wrongTeam(leaf)
        }
    }

    static func checkSpctl(status: Int32, output: String) throws {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard status == 0,
              lines.contains(where: { $0.hasSuffix(": accepted") }),
              lines.contains("source=Notarized Developer ID")
        else {
            throw VerificationError.gatekeeperRejected(lines.joined(separator: " "))
        }
    }
}
