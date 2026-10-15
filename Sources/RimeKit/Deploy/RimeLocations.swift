import Darwin
import Foundation

/// 鼠须管、Rime 用户目录、Rime 日志目录在哪。测试时换成临时目录。
public struct RimeLocations: Sendable, Equatable {
    public var rimeDirectory: URL
    public var squirrelApp: URL
    public var logDirectory: URL

    public init(rimeDirectory: URL, squirrelApp: URL, logDirectory: URL) {
        self.rimeDirectory = rimeDirectory
        self.squirrelApp = squirrelApp
        self.logDirectory = logDirectory
    }

    /// 当前用户的 ~/Library/Rime、系统里的鼠须管、$TMPDIR/rime.squirrel
    public static var `default`: RimeLocations {
        RimeLocations(
            rimeDirectory: homeDirectory().appending(path: "Library/Rime", directoryHint: .isDirectory),
            squirrelApp: URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app", isDirectory: true),
            logDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appending(path: "rime.squirrel", directoryHint: .isDirectory))
    }

    public var squirrelBinary: URL { squirrelApp.appending(path: "Contents/MacOS/Squirrel") }
    public var deployerBinary: URL { squirrelApp.appending(path: "Contents/MacOS/rime_deployer") }
    public var sharedSupport: URL { squirrelApp.appending(path: "Contents/SharedSupport", directoryHint: .isDirectory) }

    public var squirrelInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: deployerBinary.path)
    }

    /// 已安装的鼠须管版本（Info.plist 的 CFBundleVersion；1.1.2 没有 CFBundleShortVersionString）
    public var installedSquirrelVersion: String? {
        let plist = squirrelApp.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (dict["CFBundleVersion"] as? String) ?? (dict["CFBundleShortVersionString"] as? String)
    }

    /// 用 passwd 里的家目录（sudo -u 运行时 $HOME 可能还是原来的用户）
    static func homeDirectory() -> URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
