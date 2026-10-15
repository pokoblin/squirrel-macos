import Foundation
import Yams

public struct ColorSchemeInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 包里能选的配色：squirrel.yaml 的 preset_color_schemes，加上包自带补丁 squirrel.custom.yaml 里的
public enum ColorSchemes {
    public static func available(in packages: [CachedPackage]) throws -> [ColorSchemeInfo] {
        var result: [String: ColorSchemeInfo] = [:]
        for package in packages {
            for file in ["squirrel.yaml", "squirrel.custom.yaml"] where package.info.files.contains(file) {
                let text = try TextFile.read(package.filesDirectory.appending(path: file))
                guard let root = try YAMLNode.parse(text) else { continue }
                let presets = file == "squirrel.yaml" ? root["preset_color_schemes"] : root["patch"]?["preset_color_schemes"]
                for (key, value) in presets?.mapping ?? [:] {
                    guard let id = key.string, result[id] == nil else { continue }
                    result[id] = ColorSchemeInfo(id: id, name: value["name"]?.string ?? id)
                }
            }
        }
        return result.values.sorted { $0.id < $1.id }
    }
}
