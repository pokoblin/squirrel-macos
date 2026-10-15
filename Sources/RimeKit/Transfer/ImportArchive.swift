import Foundation

/// 解压、检查导出文件。导出文件当作不可信数据：只认需要的几样普通文件
public struct ImportArchive: Sendable, Equatable {
    public let manifest: ExportManifest
    /// 解压后的个人词库，按文件名排序
    public let personalDicts: [URL]
    public let phrases: [Phrase]
    /// 词典名 → 解压后的快照文件
    public let userDB: [String: URL]
    public let warnings: [String]

    /// 解压到 dir，检查格式。不碰 Rime 目录和应用数据
    public static func open(_ file: URL, catalog: Catalog, into dir: URL) throws -> ImportArchive {
        guard FileManager.default.fileExists(atPath: file.path) else { throw TransferError.notAnExport(file.path) }
        do {
            try Unzipper().unzip(file, into: dir)   // ditto 会去掉 ../，不会写到 dir 外面（已实测）
        } catch {
            throw TransferError.notAnExport(file.path)
        }
        let manifestURL = dir.appending(path: "manifest.json")
        guard isRegular(manifestURL), let data = try? Data(contentsOf: manifestURL) else { throw TransferError.notAnExport(file.path) }
        struct Header: Decodable { let formatVersion: Int }
        guard let header = try? JSONCoding.decoder.decode(Header.self, from: data) else { throw TransferError.notAnExport(file.path) }
        guard header.formatVersion == ExportManifest.currentFormatVersion else { throw TransferError.unsupportedFormat(header.formatVersion) }
        let manifest: ExportManifest
        do {
            manifest = try JSONCoding.decoder.decode(ExportManifest.self, from: data)
        } catch {
            throw TransferError.badContent("manifest.json：\(error)")
        }
        do {
            try manifest.settings.validate(catalog)
        } catch let error as SettingsError {
            switch error {
            case .unknownSchema, .unknownOption, .unknownChoice:
                throw TransferError.unknownToCatalog(String(describing: error))
            default:
                throw TransferError.badSettings(String(describing: error))
            }
        }

        var warnings: [String] = []
        // personal、personal/dicts、userdb 本身必须是真的文件夹：是符号链接的话会读到解压目录外面
        func folder(_ path: String) -> URL? {
            let url = dir.appending(path: path, directoryHint: .isDirectory)
            guard let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType else { return nil }
            guard type == .typeDirectory else {
                warnings.append("导出文件里的 \(path) 不是普通文件夹，跳过")
                return nil
            }
            return url
        }
        let personalDir = folder("personal")
        var dicts: [URL] = []
        if personalDir != nil, let dictsDir = folder("personal/dicts") {
            for (name, url) in entries(dictsDir) {
                if name.hasSuffix(".dict.yaml"), isRegular(url) {
                    dicts.append(url)
                } else {
                    warnings.append("导出文件里的 personal/dicts/\(name) 不是个人词库，跳过")
                }
            }
        }
        var phrases: [Phrase] = []
        if let personalDir {
            let phrasesURL = personalDir.appending(path: "phrases.txt")
            if FileManager.default.fileExists(atPath: phrasesURL.path) {
                guard isRegular(phrasesURL), let text = try? String(contentsOf: phrasesURL, encoding: .utf8) else {
                    throw TransferError.badContent("personal/phrases.txt 读不了")
                }
                phrases = PhraseFile.parse(text)
            }
        }
        var userDB: [String: URL] = [:]
        if let userDBDir = folder("userdb") {
            for (name, url) in entries(userDBDir) {
                let dict = name.hasSuffix(".userdb.txt") ? String(name.dropLast(".userdb.txt".count)) : ""
                if RimeDictManager.isValidName(dict), isRegular(url) {
                    userDB[dict] = url
                } else {
                    warnings.append("导出文件里的 userdb/\(name) 不是输入习惯快照，跳过")
                }
            }
        }
        return ImportArchive(manifest: manifest, personalDicts: dicts, phrases: phrases, userDB: userDB, warnings: warnings)
    }

    /// 目录里的条目（不含隐藏文件），按名字排序；目录不存在时为空
    static func entries(_ dir: URL) -> [(String, URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { ($0, dir.appending(path: $0)) }
    }

    /// 普通文件（不是目录、不是符号链接）
    static func isRegular(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular
    }
}
