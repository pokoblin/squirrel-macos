import Foundation

public enum UnzipError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(status: Int32, message: String)
    case tooLarge(Int64)

    public var description: String {
        switch self {
        case let .failed(status, message):
            return "解压失败（ditto 退出码 \(status)）：\(message)"
        case .tooLarge(let size):
            return "这个文件解开后有 \(size / 1_000_000) MB，太大了，没有解开（可能文件坏了）"
        }
    }
}

/// 用系统自带的 ditto 解压（干净的 macOS 27 上已验证可用，见 verified-facts）
public struct Unzipper: Sendable {
    /// 解开后的总大小上限（设计第 7 节：坏的或者意外的大文件不要塞满磁盘）。
    /// 看的是 zip 里写的大小：挡得住损坏的、意外的大文件，挡不住故意改小的
    let maxBytes: Int64

    public init(maxBytes: Int64 = 2_000_000_000) {
        self.maxBytes = maxBytes
    }

    public func unzip(_ zip: URL, into directory: URL) throws {
        let size = try Self.uncompressedSize(zip)
        guard size <= maxBytes else { throw UnzipError.tooLarge(size) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
        guard result.status == 0 else {
            throw UnzipError.failed(status: result.status, message: result.stderr)
        }
    }
}

extension Unzipper {
    /// zipinfo -t 的最后一行：「N files, X bytes uncompressed, Y bytes compressed: Z%」
    static func uncompressedSize(_ zip: URL) throws -> Int64 {
        let r = try Shell.run("/usr/bin/zipinfo", ["-t", zip.path])
        guard r.status == 0, let range = r.stdout.range(of: #"(\d+) bytes uncompressed"#, options: .regularExpression),
              let size = Int64(r.stdout[range].split(separator: " ")[0]) else {
            throw UnzipError.failed(status: r.status, message: "看不出 zip 解开后有多大：\(r.stderr)")
        }
        return size
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
