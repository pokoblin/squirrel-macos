import Foundation

/// 导出文件里的 manifest.json（设计第 5 节「导出文件」）
public struct ExportManifest: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public struct Package: Sendable, Equatable, Codable {
        public let id: String
        public let version: String

        public init(id: String, version: String) {
            self.id = id
            self.version = version
        }
    }

    public var formatVersion: Int
    public var exportedAt: Date
    public var settings: Settings
    /// 导出时用的上游版本：只用来参考和排查问题，导入时总是下载最新版
    public var packages: [Package]
    /// personal/dicts 里的文件名
    public var personalDicts: [String]
    /// personal/phrases.txt 里的条数
    public var phrases: Int
    /// userdb 里的输入习惯（词典名）
    public var userDB: [String]

    public init(formatVersion: Int, exportedAt: Date, settings: Settings, packages: [Package],
                personalDicts: [String], phrases: Int, userDB: [String]) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.packages = packages
        self.personalDicts = personalDicts
        self.phrases = phrases
        self.userDB = userDB
    }
}

public enum TransferError: Error, Equatable, Sendable, CustomStringConvertible {
    case noSettings
    case targetExists(String)
    case targetNotAFile(String)
    case notAnExport(String)
    case unsupportedFormat(Int)
    case badSettings(String)
    case badContent(String)
    /// 导入出错；previous 是导入前另存的设置和个人内容
    case importFailed(String, previous: String)

    public var description: String {
        switch self {
        case .noSettings:
            return "还没有设置，没什么可导出的。先 rimectl takeover 接管已有配置，或 rimectl settings init 选一个起步方案"
        case .targetExists(let path):
            return "\(path) 已经有了。要覆盖就加 --force"
        case .targetNotAFile(let path):
            return "\(path) 是文件夹（或别的不是普通文件的东西），不能当导出文件。请写一个文件名，例如 \(path)/squirrel-macos-导出.zip"
        case .notAnExport(let path):
            return "\(path) 不是 squirrel-macos 的导出文件"
        case .unsupportedFormat(let v):
            return "导出文件的格式版本是 \(v)，这个版本的应用只认识 \(ExportManifest.currentFormatVersion)，请更新应用"
        case .badSettings(let message):
            return "导出文件里的设置用不了：\(message)"
        case .badContent(let message):
            return "导出文件坏了：\(message)"
        case let .importFailed(message, previous):
            return "导入失败：\(message)。应用里原来的设置和个人内容另存在 \(previous)，需要时可以用 rimectl import 这个文件找回"
        }
    }
}
