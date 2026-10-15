import Foundation
@testable import RimeKit

/// 给生成器用的三个自造包。内容是能被 rime_deployer 编译的最小方案。
enum GenFixtures {
    static let catalogJSON = """
    {"formatVersion":1,"packages":[
     {"id":"pinyin","name":"测试拼音","summary":"s","license":"MIT","homepage":"https://example.com/p",
      "source":{"type":"githubReleaseAsset","repo":"o/p","tag":"t","asset":"p.zip"},
      "anchor":"py.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["py.schema.yaml"],
      "schemas":[{"id":"py","name":"拼音","category":"pinyin"},{"id":"sp","name":"双拼","category":"shuangpin"}],
      "dependencies":[]},
     {"id":"words","name":"词库","summary":"s","license":"MIT","homepage":"https://example.com/w",
      "source":{"type":"githubReleaseAsset","repo":"o/w","tag":"t","asset":"w.zip"},
      "anchor":"cn/a.dict.yaml","include":["cn/*"],"exclude":[],"requiredFiles":["cn/a.dict.yaml"],
      "schemas":[],"dependencies":[]},
     {"id":"wubi","name":"测试五笔","summary":"s","license":"MIT","homepage":"https://example.com/wb",
      "source":{"type":"githubBranch","repo":"o/wb","branch":"main"},
      "anchor":"wb.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["wb.schema.yaml"],
      "schemas":[{"id":"wb","name":"五笔","category":"wubi"},{"id":"wb_py","name":"五笔拼音","category":"wubi"},{"id":"wpy","name":"五笔里的拼音","category":"pinyin"}],
      "dependencies":[],"userDicts":["wb_user.dict.yaml"],
      "options":[{"id":"pinyinDictionary","name":"拼音词库","defaultChoice":"ext","choices":[
        {"id":"builtin","name":"自带","dependencies":[],"generatedDicts":[],"patches":{}},
        {"id":"ext","name":"大词库","dependencies":["words"],
         "generatedDicts":[{"name":"py_ext","importTables":[{"name":"py_user","onlyIfPersonal":true},{"name":"cn/a"}]}],
         "patches":{"wpy":{"translator/dictionary":"py_ext"},"wb":{"reverse_lookup/dictionary":"py_ext"},"wb_py":{"reverse_lookup/dictionary":"py_ext"}}}
      ]}]}
    ]}
    """

    static func catalog() throws -> Catalog {
        try Catalog.decode(Data(catalogJSON.utf8))
    }

    static func pinyinSchema(id: String, name: String, dictionary: String, phraseFile: String?) -> String {
        let translators = phraseFile == nil
            ? "    - script_translator"
            : "    - table_translator@custom_phrase\n    - script_translator"
        let phrase = phraseFile.map {
            "custom_phrase:\n  dictionary: \"\"\n  user_dict: \($0)\n  db_class: stabledb\n  enable_completion: false\n  enable_sentence: false\n  initial_quality: 99\n"
        } ?? ""
        return """
        schema:
          schema_id: \(id)
          name: \(name)
          version: "1"
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
        \(translators)
        speller:
          alphabet: zyxwvutsrqponmlkjihgfedcba
          delimiter: " '"
        translator:
          dictionary: \(dictionary)
          enable_sentence: false

        """ + phrase
    }

    static func wubiSchema(id: String) -> String {
        """
        schema:
          schema_id: \(id)
          name: 测试五笔 \(id)
          version: "1"
          dependencies:
            - wpy
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
            - reverse_lookup_translator
        speller:
          alphabet: zyxwvutsrqponmlkjihgfedcba
        translator:
          dictionary: wb
          enable_sentence: false
        abc_segmentor:
          extra_tags:
            - reverse_lookup
        reverse_lookup:
          dictionary: wpy

        """
    }

    static func dict(_ name: String, _ entries: [String]) -> String {
        "---\nname: \(name)\nversion: \"1\"\nsort: by_weight\n...\n" + entries.map { $0 + "\n" }.joined()
    }

    static let files: [String: [String: String]] = [
        "pinyin": [
            "py.schema.yaml": pinyinSchema(id: "py", name: "测试拼音", dictionary: "py", phraseFile: "custom_phrase"),
            "sp.schema.yaml": pinyinSchema(id: "sp", name: "测试双拼", dictionary: "py", phraseFile: "custom_phrase_double"),
            "py.dict.yaml": dict("py", ["你\tni\t100", "好\thao\t100", "你好\tni hao\t1000"]),
            "custom_phrase.txt": "# Rime table\n#@/db_name\tcustom_phrase.txt\n#@/db_type\ttabledb\n#\n上游短语\tsy\t1\n",
            "squirrel.yaml": "style:\n  color_scheme: aqua\n  font_point: 16\npreset_color_schemes:\n  aqua:\n    name: 碧水\n",
            "LICENSE": "MIT\n",
        ],
        "words": [
            "cn/a.dict.yaml": dict("a", ["你好\tni hao\t5000", "大词库\tda ci ku\t100"]),
        ],
        "wubi": [
            "wb.schema.yaml": wubiSchema(id: "wb"),
            "wb_py.schema.yaml": wubiSchema(id: "wb_py"),
            "wpy.schema.yaml": pinyinSchema(id: "wpy", name: "五笔里的拼音", dictionary: "wpy", phraseFile: nil),
            "wb.dict.yaml": dict("wb", ["一\tg\t100", "工\ta\t100"]),
            "wpy.dict.yaml": dict("wpy", ["拼\tpin\t1"]),
            "wb_user.dict.yaml": dict("wb_user", []),
            "default.custom.yaml": """
            patch:
              schema_list:
                - schema: wb
                - schema: wb_py
              menu:
                page_size: 5
              key_binder:
                bindings:
                  - { when: has_menu, accept: bracketleft, send: Page_Up }

            """,
            "squirrel.custom.yaml": """
            patch:
              style:
                color_scheme: roseo
                color_scheme_dark: roseo_dark
              preset_color_schemes:
                roseo:
                  name: 玫枫
                  font_point: 18
                  label_font_point: 17
                roseo_dark:
                  name: 玫枫暗
                  font_point: 18

            """,
            "LICENSE": "MIT\n",
        ],
    ]

    /// 把三个包写成缓存目录的格式：root/<id>@v1/{package.json, files/…}。
    /// extra：再往某个包里加文件（包 id → 路径 → 内容）
    static func makePackages(in root: URL, extra: [String: [String: String]] = [:]) throws -> [String: CachedPackage] {
        let fm = FileManager.default
        let catalog = try catalog()
        var result: [String: CachedPackage] = [:]
        for (id, baseFiles) in files {
            guard let spec = catalog.package(id) else { fatalError("清单里没有 \(id)") }
            let all = baseFiles.merging(extra[id] ?? [:]) { _, new in new }
            let dir = root.appending(path: PackageStore.directoryName(id: id, version: "v1"), directoryHint: .isDirectory)
            let filesDir = dir.appending(path: "files", directoryHint: .isDirectory)
            for (path, text) in all {
                let url = filesDir.appending(path: path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            let info = PackageInfo(id: id, version: "v1", sourceURL: URL(string: "https://example.com/\(id).zip")!,
                                   zipSHA256: String(repeating: "0", count: 64), fetchedAt: Date(timeIntervalSince1970: 1_000),
                                   files: all.keys.sorted(), rules: PackageStore.rulesFingerprint(spec))
            try JSONCoding.encoder.encode(info).write(to: dir.appending(path: "package.json"))
            result[id] = CachedPackage(info: info, filesDirectory: filesDir)
        }
        return result
    }

    static func input(
        _ settings: Settings,
        packages: [String: CachedPackage],
        personal: PersonalContent = .empty,
        textReplacement: [Phrase] = []
    ) throws -> GenerationInput {
        GenerationInput(settings: settings, catalog: try catalog(), packages: packages,
                        personal: personal, textReplacementPhrases: textReplacement)
    }

    static func read(_ out: URL, _ path: String) throws -> String {
        try String(contentsOf: out.appending(path: path), encoding: .utf8)
    }

    static func patch(_ out: URL, _ name: String) throws -> Patch {
        try Patch.parse(customYAML: read(out, "\(name).custom.yaml"))
    }

    static func exists(_ out: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: out.appending(path: path).path)
    }
}
