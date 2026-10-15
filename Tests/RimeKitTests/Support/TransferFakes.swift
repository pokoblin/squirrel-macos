import Foundation
@testable import RimeKit

/// 假的 rime_dict_manager：输入习惯存在内存里；前几次调用可以假装被鼠须管占着
final class FakeUserDBTool: UserDBTool, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String]
    private var failures: Int
    private var log: [String] = []

    init(dbs: [String: String] = [:], lockedFailures: Int = 0) {
        stored = dbs
        failures = lockedFailures
    }

    var dbs: [String: String] { lock.withLock { stored } }
    var calls: [String] { lock.withLock { log } }

    func list() throws -> [String] { lock.withLock { stored.keys.sorted() } }

    func export(_ name: String, to file: URL) throws {
        let text: String? = try lock.withLock {
            if failures > 0 { failures -= 1; throw UserDBError.locked(name) }
            log.append("export \(name)")
            return stored[name]
        }
        guard let text else { throw UserDBError.failed(name, "没有这个输入习惯") }
        try Data(text.utf8).write(to: file)
    }

    func importSnapshot(_ name: String, from file: URL) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        try lock.withLock {
            if failures > 0 { failures -= 1; throw UserDBError.locked(name) }
            log.append("import \(name)")
            stored[name] = (stored[name] ?? "") + text
        }
    }
}

/// 一台假的 Mac：应用数据目录、Rime 目录、假的鼠须管、假的 rime_dict_manager、三个自造包
enum TransferFixtures {
    struct Machine {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let squirrel: FakeSquirrel
        let tool: FakeUserDBTool
        let catalog: Catalog
        let packages: [String: CachedPackage]

        var userDB: UserDBTransfer { UserDBTransfer(tool: tool, squirrel: squirrel, sleep: { _ in }) }

        func deployer(_ compiler: FakeCompiler = FakeCompiler()) -> Deployer {
            Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                     watcher: DeployFixtures.watcher(locations))
        }

        func exporter(userDB: Bool = true) -> Exporter {
            Exporter(paths: paths, locations: locations, userDB: userDB ? self.userDB : nil, now: { TransferFixtures.date })
        }
    }

    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let settings = Settings(schemas: ["wb_py", "py"], options: ["wubi": ["pinyinDictionary": "ext"]],
                                   appearance: Appearance(fontPoint: 22))
    static let phrase = Phrase(text: "私人短语", code: "srdy", weight: 1)
    static let pyUser = GenFixtures.dict("py_user", ["私人词条\tsi ren ci tiao\t100"])
    static let snapshot = "# Rime user dictionary export\n#@/db_name\twb_py\n#@/db_type\tuserdb\nni hao \t你好\t0\n"

    static func machine(withSettings: Bool = true, userDB: [String: String] = ["wb_py": snapshot],
                        running: Bool = true) throws -> Machine {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let packages = try GenFixtures.makePackages(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        if withSettings {
            try SettingsStore(paths: paths).save(settings)
            try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
            try Data(pyUser.utf8).write(to: paths.personalDicts.appending(path: "py_user.dict.yaml"))
            try Data((PhraseFile.header + PhraseFile.render([phrase])).utf8).write(to: paths.personalPhrases)
        }
        return Machine(dir: dir, paths: paths, locations: locations,
                       squirrel: FakeSquirrel(locations: locations, running: running),
                       tool: FakeUserDBTool(dbs: userDB), catalog: try GenFixtures.catalog(), packages: packages)
    }

    /// 目录里所有普通文件的相对路径
    static func files(in dir: URL) throws -> Set<String> {
        var result = Set<String>()
        for path in try FileManager.default.subpathsOfDirectory(atPath: dir.path) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.appending(path: path).path, isDirectory: &isDir), !isDir.boolValue {
                result.insert(path)
            }
        }
        return result
    }
}
