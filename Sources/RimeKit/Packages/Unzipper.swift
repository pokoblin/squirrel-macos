import Foundation

public enum UnzipError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(status: Int32, message: String)

    public var description: String {
        switch self {
        case let .failed(status, message):
            return "解压失败（ditto 退出码 \(status)）：\(message)"
        }
    }
}

/// 用系统自带的 ditto 解压（干净的 macOS 27 上已验证可用，见 verified-facts）
public struct Unzipper: Sendable {
    public init() {}

    public func unzip(_ zip: URL, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
        guard result.status == 0 else {
            throw UnzipError.failed(status: result.status, message: result.stderr)
        }
    }
}

public enum ZipError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(status: Int32, message: String)

    public var description: String {
        switch self {
        case let .failed(status, message):
            return "打包失败（ditto 退出码 \(status)）：\(message)"
        }
    }
}

/// 用系统自带的 ditto 打包：zip 里直接是目录里的内容；不带资源分支和扩展属性（不然会多出 __MACOSX/，已实测）
public struct Zipper: Sendable {
    public init() {}

    public func zip(_ directory: URL, to file: URL) throws {
        let result = try Shell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", directory.path, file.path])
        guard result.status == 0 else {
            throw ZipError.failed(status: result.status, message: result.stderr)
        }
    }
}
