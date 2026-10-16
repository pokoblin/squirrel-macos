import Foundation
@testable import RimeKit

/// 迷你极点五笔包：同样的包 id、同样的文件名，内容是编的（只有三十来个字和几个词）。
/// 词库头部的 `encoder` 段是真包里的原文。
enum WubiFixtures {
    static let packageID = "wubi86-jidian"
    static let mainName = "wubi86_jidian.dict.yaml"
    static let userName = "wubi86_jidian_user.dict.yaml"
    static let hamsterName = "wubi86_jidian_user_hamster.dict.yaml"
    static let extraName = "wubi86_jidian_extra.dict.yaml"

    static let catalogJSON = """
    {"formatVersion":1,"packages":[
     {"id":"wubi86-jidian","name":"测试极点五笔","summary":"s","license":"MIT","homepage":"https://example.com/jd",
      "source":{"type":"githubBranch","repo":"o/jd","branch":"main"},
      "anchor":"wubi86_jidian.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["wubi86_jidian.schema.yaml"],
      "schemas":[{"id":"wubi86_jidian","name":"极点五笔","category":"wubi"}],
      "dependencies":[],"userDicts":["wubi86_jidian_user.dict.yaml"]}
    ]}
    """

    /// 主词库。字和编码都是编的（张三丰、戈等只是为了凑出各种情况）：
    /// - 张 xt/xta/xtay、三 dg/dgg/dggg、丰 dh/dhk：和真词库一样
    /// - 戈：两个一样长的四码全码（afny、ghny）
    /// - 泳：z 开头的更长编码（ziyiy）不算
    static let mainDict = """
    # Rime dictionary: 测试用的迷你极点五笔
    ---
    name: wubi86_jidian
    version: "test"
    sort: by_weight
    columns:
      - text
      - code
      - weight
      - stem
    import_tables:
      - wubi86_jidian_user       # 用户词库
      - wubi86_jidian_user_hamster
      - wubi86_jidian_extra      # 扩展词库
    encoder:
      exclude_patterns:
        - '^z.*$'
      rules:                        # 大写字母表示字序，小写字母表示其所跟随的大写字母所以表的字中的编码序
        - length_equal: 2           # 对于二字词
          formula: "AaAbBaBb"       # 取第一字首二码、第二字首二码
        - length_equal: 3           # 对于三字词
          formula: "AaBaCaCb"       # 取第一字首码、第二字首码、第三字首码、第三字二笔码
        - length_in_range: [4, 10]  # 对于四至十字词
          formula: "AaBaCaZa"       # 取第一字首码，第二字尾码、第三字首码、最后一字尾码
    ...
    张\txt\t100\t
    张\txta\t100\t
    张\txtay\t100\txtay
    三\tdg\t100\t
    三\tdgg\t100\t
    三\tdggg\t100\tdggg
    丰\tdh\t100\t
    丰\tdhk\t100\tdhk
    戈\tafny\t90\tafny
    戈\tghny\t80\tghny
    五\tgg\t100\t
    五\tgghg\t100\tgghg
    仰\twq\t100\t
    仰\twqbh\t100\twqbh
    泳\tiy\t100\t
    泳\tiyiy\t100\tiyiy
    泳\tziyiy\t100\t
    你\twqiy\t20
    你\twq\t10
    一\tg\t100
    二\tfg\t100
    四\tlh\t100
    六\tuy\t100
    七\tag\t100
    八\tws\t100
    九\tvt\t100
    十\tfh\t100
    大\tdd\t100
    小\tihty\t100
    山\tmmm\t100
    水\tiyi\t100
    火\too\t100
    木\tssss\t100
    土\tffg\t100
    仰泳\twqiy\t10
    张三\txtdg\t50
    """

    /// 个人词库，和上游一样的写法：`sort: original`，`dict_grouped: true`
    static let userDict = """
    ---
    name: wubi86_jidian_user
    version: "test"
    sort: original
    dict_grouped: true
    ...
    ## 示例
    分组词条\twxyt
    """

    static let hamsterDict = "---\nname: wubi86_jidian_user_hamster\nversion: \"test\"\nsort: original\n...\n"
    static let extraDict = "---\nname: wubi86_jidian_extra\nversion: \"test\"\nsort: by_weight\n...\n"

    static let schema = """
    schema:
      schema_id: wubi86_jidian
      name: 极点五笔（测试）
      version: "test"
    engine:
      processors:
        - ascii_composer
        - key_binder
        - speller
        - selector
        - navigator
        - express_editor
      segmentors:
        - ascii_segmentor
        - abc_segmentor
        - fallback_segmentor
      translators:
        - table_translator
    speller:
      alphabet: zyxwvutsrqponmlkjihgfedcba
      max_code_length: 4
    translator:
      dictionary: wubi86_jidian
      enable_sentence: false
      enable_user_dict: false

    """

    static let defaultCustom = "patch:\n  schema_list:\n    - schema: wubi86_jidian\n"

    /// 包里的所有文件（路径 → 内容）
    static var files: [String: String] {
        [
            mainName: mainDict,
            userName: userDict,
            hamsterName: hamsterDict,
            extraName: extraDict,
            "wubi86_jidian.schema.yaml": schema,
            "default.custom.yaml": defaultCustom,
        ]
    }

    static func catalog() throws -> Catalog {
        try Catalog.decode(Data(catalogJSON.utf8))
    }

    /// 写成缓存目录的格式：cache/<id>@v1/{package.json, files/…}（和 GenFixtures.makePackages 一样）
    static func makePackage(in cache: URL) throws -> CachedPackage {
        let fm = FileManager.default
        guard let spec = try catalog().package(packageID) else { fatalError("清单里没有 \(packageID)") }
        let dir = cache.appending(path: PackageStore.directoryName(id: packageID, version: "v1"), directoryHint: .isDirectory)
        let filesDir = dir.appending(path: "files", directoryHint: .isDirectory)
        for (path, text) in files {
            let url = filesDir.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let info = PackageInfo(
            id: packageID, version: "v1", sourceURL: URL(string: "https://example.com/\(packageID).zip")!,
            zipSHA256: String(repeating: "0", count: 64), fetchedAt: Date(timeIntervalSince1970: 1_000),
            files: files.keys.sorted(), rules: PackageStore.rulesFingerprint(spec))
        try JSONCoding.encoder.encode(info).write(to: dir.appending(path: "package.json"))
        return CachedPackage(info: info, filesDirectory: filesDir)
    }

    struct CompileFailed: Error, CustomStringConvertible {
        let stderr: String
        var description: String { "五笔夹具编译失败：\(stderr)" }
    }

    /// 把夹具文件写进 dir（可换掉个人词库的内容），用 rime_deployer 编译，返回 dir。
    /// extraFiles：另外写进去或换掉的文件（文件名 → 内容），比如换掉 hamster 词库
    @discardableResult
    static func compiled(in dir: URL, userDict: String? = nil, extraFiles: [String: String] = [:]) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var all = files
        if let userDict { all[userName] = userDict }
        all.merge(extraFiles) { _, new in new }
        for (path, text) in all {
            try Data(text.utf8).write(to: dir.appending(path: path))
        }
        let r = try RimeTools.build(dir)
        guard r.status == 0 else { throw CompileFailed(stderr: r.stderr) }
        return dir
    }
}
