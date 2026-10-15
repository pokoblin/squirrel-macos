import Foundation

/// 读写 settings.json
public struct SettingsStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    /// 还没有设置文件时返回 nil。先只读格式版本号，版本不对就不往下解析。
    public func load() throws -> Settings? {
        guard FileManager.default.fileExists(atPath: paths.settingsFile.path) else { return nil }
        let data = try Data(contentsOf: paths.settingsFile)
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONCoding.decoder.decode(Header.self, from: data)
        guard header.formatVersion == Settings.currentFormatVersion else {
            throw SettingsError.unsupportedFormat(header.formatVersion)
        }
        return try JSONCoding.decoder.decode(Settings.self, from: data)
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(settings).write(to: paths.settingsFile, options: .atomic)
    }
}
