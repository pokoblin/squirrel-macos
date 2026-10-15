import Foundation
import Yams

/// 认出来的东西（设计 6.2）：用户确认后保存成设置和个人内容，再按 6.1 应用
public struct TakeoverProposal: Sendable, Equatable {
    public var settings: Settings
    /// 要收进 personal/dicts 的个人词库（现在在 Rime 目录里的位置），按文件名排序
    public var personalDicts: [URL]
    /// 要收进 personal/phrases.txt 的手动短语
    public var manualPhrases: [Phrase]
    /// 短语文件里和 macOS 文本替换一样的条数：这些不算手动短语，接管后由文本替换同步生成
    public var textReplacementMatches: Int
    /// 要告诉用户的地方：认不出的、接管后会变的
    public var notes: [String]

    public init(settings: Settings, personalDicts: [URL], manualPhrases: [Phrase], textReplacementMatches: Int, notes: [String]) {
        self.settings = settings
        self.personalDicts = personalDicts
        self.manualPhrases = manualPhrases
        self.textReplacementMatches = textReplacementMatches
        self.notes = notes
    }

    /// 按识别结果生成配置用的输入（文本替换同步打开时才带上文本替换）
    public func generationInput(catalog: Catalog, packages: [String: CachedPackage], textReplacement: [Phrase]) -> GenerationInput {
        GenerationInput(settings: settings, catalog: catalog, packages: packages,
                        personal: PersonalContent(dicts: personalDicts, phrases: manualPhrases),
                        textReplacementPhrases: settings.textReplacement.sync ? textReplacement : [])
    }
}

/// 认出已有 Rime 目录里的配置。只读，不改任何文件。规则见设计 5.2。
public enum TakeoverAnalyzer {
    public static func analyze(_ rime: URL, catalog: Catalog, survey: TakeoverSurvey,
                               packages: [String: CachedPackage], textReplacement: [Phrase]) throws -> TakeoverProposal {
        guard !survey.schemas.isEmpty else { throw TakeoverError.nothingRecognized }
        return try TakeoverAnalysis(rime: rime, catalog: catalog, survey: survey, packages: packages,
                                    textReplacement: textReplacement).run()
    }
}

/// 一次识别的过程和中间状态
final class TakeoverAnalysis {
    static let appearanceKeys = ["font_point", "label_font_point", "comment_font_point", "candidate_list_layout", "text_orientation"]
    static let phraseTranslator = "table_translator@custom_phrase"

    struct Schemes {
        var light: String?
        var dark: String?
        var baseLight: String?
        var baseDark: String?
    }

    let rime: URL
    let catalog: Catalog
    let survey: TakeoverSurvey
    let packages: [String: CachedPackage]
    let textReplacement: [Phrase]
    let specs: [PackageSpec]
    let files: Set<String>
    /// 配置名 → Rime 目录里现在的补丁
    var existing: [String: Patch] = [:]
    /// 配置名 → 不接管时生成器会写的默认补丁：上游自带的 + 所选选项的
    var expected: [String: Patch] = [:]
    var chosen: [OptionChoice] = []
    var schemes = Schemes()
    var notes: [String] = []

    init(rime: URL, catalog: Catalog, survey: TakeoverSurvey, packages: [String: CachedPackage], textReplacement: [Phrase]) throws {
        self.rime = rime.resolvingSymlinksInPath()
        self.catalog = catalog
        self.survey = survey
        self.packages = packages
        self.textReplacement = textReplacement
        specs = try catalog.installOrder(for: survey.packages)
        for spec in specs where packages[spec.id] == nil { throw TakeoverError.missingPackage(spec.id) }
        files = Set(try RimeFiles.configFiles(in: rime))
    }

    func run() throws -> TakeoverProposal {
        try loadPatches()
        noteUnsupported()
        let options = detectOptions()
        let personalDicts = detectPersonalDicts()
        try checkGeneratedDicts(personal: personalDicts)
        let appearance = try detectAppearance()
        var preserved: [String: [PreservedPatch]] = [:]
        for name in existing.keys.sorted() {
            let items = try preservedItems(name)
            if !items.isEmpty { preserved[name] = items }
        }
        let (manual, matches) = try detectPhrases()
        if !survey.unknownSchemas.isEmpty {
            notes.append("方案列表里的 \(survey.unknownSchemas.joined(separator: "、")) 不在方案清单里，接管后不会出现在方案列表里（文件原样保留）")
        }
        let settings = Settings(schemas: survey.schemas, options: options, appearance: appearance,
                                textReplacement: TextReplacementSettings(sync: matches > 0), preservedPatches: preserved)
        try settings.validate(catalog)
        return TakeoverProposal(settings: settings, personalDicts: personalDicts, manualPhrases: manual,
                                textReplacementMatches: matches, notes: notes)
    }

    // MARK: 读补丁（规则 1）

    func loadPatches() throws {
        var names = ["default", "squirrel"]
        for spec in specs {
            names += spec.schemas.map(\.id)
            names += upstreamPatchNames(spec)
        }
        for name in names where existing[name] == nil {
            let file = "\(name).custom.yaml"
            guard files.contains(file), let text = try TakeoverFiles.read(rime, file) else { continue }
            existing[name] = try TakeoverFiles.patch(text, file: file)
        }
        for spec in specs {
            let package = packages[spec.id]!
            for name in upstreamPatchNames(spec) {
                let path = "\(name).custom.yaml"
                let text = try TextFile.read(package.filesDirectory.appending(path: path))
                expected[name, default: Patch()].merge(try TakeoverFiles.patch(text, file: "\(spec.id)/\(path)"))
            }
        }
    }

    /// 这个应用认不出、接管后不保留的写法：在预览里告诉用户
    func noteUnsupported() {
        let list = PatchLeaves(existing["default"] ?? Patch())["schema_list"]?.sequence ?? []
        if list.contains(where: { item in (item.mapping.map { Array($0.keys) } ?? []).contains { $0.string != "schema" } }) {
            notes.append("default.custom.yaml 的 schema_list 里有 schema 以外的写法（例如 case:），接管后不保留，方案顺序照旧")
        }
        for file in files.sorted() where file.hasSuffix(".custom.yaml") {
            guard let text = try? TakeoverFiles.read(rime, file), let root = try? YAMLNode.parse(text),
                  let keys = root.mapping?.keys.compactMap(\.string),
                  keys.contains("__patch") || keys.contains("__include") else { continue }
            notes.append("\(file) 用了 __patch / __include，这个应用认不出，接管后不保留")
        }
        for file in files.sorted() where (try? FileManager.default.destinationOfSymbolicLink(atPath: rime.appending(path: file).path)) != nil {
            notes.append("\(file) 是符号链接：接管后应用要写这个文件的话，会换成普通文件（原来的链接在备份里）")
        }
    }

    func upstreamPatchNames(_ spec: PackageSpec) -> [String] {
        packages[spec.id]!.info.files.filter(GenerationContext.isUpstreamPatch).map { String($0.dropLast(".custom.yaml".count)) }
    }

    /// 包里的文件：生成时后复制的包覆盖先复制的，所以从后往前找
    func upstreamURL(_ path: String) -> URL? {
        for spec in specs.reversed() {
            let package = packages[spec.id]!
            if package.info.files.contains(path) { return package.filesDirectory.appending(path: path) }
        }
        return nil
    }

    func upstreamYAML(_ path: String) throws -> Node? {
        guard let url = upstreamURL(path) else { return nil }
        return try TakeoverFiles.yaml(try TextFile.read(url), file: path)
    }

    // MARK: 选项（规则 2）

    func detectOptions() -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for spec in specs {
            for option in spec.options {
                var best: (choice: OptionChoice, size: Int)?
                var partial = false
                for choice in option.choices {
                    let (matched, total) = score(choice)
                    if matched == total {
                        if best == nil || total > best!.size { best = (choice, total) }
                    } else if matched > 0 {
                        partial = true
                    }
                }
                let choice = best?.choice ?? option.choice(option.defaultChoice) ?? option.choices[0]
                if best == nil {
                    notes.append("认不出「\(spec.name)」的「\(option.name)」，接管后用「\(choice.name)」")
                } else if partial {
                    notes.append("「\(spec.name)」的「\(option.name)」只认出一部分设置，接管后用「\(choice.name)」，认不出的补丁原样保留")
                }
                result[spec.id, default: [:]][option.id] = choice.id
                chosen.append(choice)
                for (schema, values) in choice.patches.sorted(by: { $0.key < $1.key }) {
                    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                        expected[schema, default: Patch()].set(key, YAMLNode.text(value))
                    }
                }
            }
        }
        return result
    }

    /// 这个选择的条件（补丁项 + 要生成的总词库）对上了几条、一共几条
    func score(_ choice: OptionChoice) -> (matched: Int, total: Int) {
        var matched = 0
        var total = 0
        for (schema, values) in choice.patches {
            let leaves = PatchLeaves(existing[schema] ?? Patch())
            for (key, value) in values {
                total += 1
                if leaves[key]?.string == value { matched += 1 }
            }
        }
        for dict in choice.generatedDicts {
            total += 1
            if files.contains("\(dict.name).dict.yaml") { matched += 1 }
        }
        return (matched, total)
    }

    // MARK: 个人词库（规则 6）

    func detectPersonalDicts() -> [URL] {
        var names: [String] = []
        for spec in specs {
            let package = packages[spec.id]!
            for file in spec.userDicts where files.contains(file) {
                let upstream = package.filesDirectory.appending(path: file)
                if FileManager.default.contentsEqual(atPath: rime.appending(path: file).path, andPath: upstream.path) { continue }
                names.append(file)
            }
        }
        for choice in chosen {
            for dict in choice.generatedDicts {
                for table in dict.importTables where table.onlyIfPersonal {
                    let file = "\(table.name).dict.yaml"
                    if files.contains(file), !names.contains(file) { names.append(file) }
                }
            }
        }
        return names.sorted().map { rime.appending(path: $0) }
    }

    func checkGeneratedDicts(personal: [URL]) throws {
        let personalNames = Set(personal.map(\.lastPathComponent))
        for choice in chosen {
            for dict in choice.generatedDicts {
                let file = "\(dict.name).dict.yaml"
                guard files.contains(file), let text = try TakeoverFiles.read(rime, file) else { continue }
                let want = dict.importTables
                    .filter { !$0.onlyIfPersonal || personalNames.contains("\($0.name).dict.yaml") }
                    .map(\.name)
                let have = TakeoverFiles.importTables(text) ?? []
                if have != want {
                    notes.append("\(file) 现在导入的词库是 \(have.joined(separator: "、"))；接管后由应用生成，导入 \(want.joined(separator: "、"))")
                }
            }
        }
    }

    // MARK: 外观（规则 4、5）

    func detectAppearance() throws -> Appearance {
        var appearance = Appearance()
        let file = try upstreamYAML("squirrel.yaml")
        let mine = PatchLeaves(existing["squirrel"] ?? Patch())
        let base = PatchLeaves(expected["squirrel"] ?? Patch())
        let baseLight = base["style/color_scheme"]?.string ?? file?["style"]?["color_scheme"]?.string
        let baseDark = base["style/color_scheme_dark"]?.string ?? file?["style"]?["color_scheme_dark"]?.string
        schemes = Schemes(light: mine["style/color_scheme"]?.string ?? baseLight,
                          dark: mine["style/color_scheme_dark"]?.string ?? baseDark,
                          baseLight: baseLight, baseDark: baseDark)
        if schemes.light != baseLight { appearance.colorScheme = schemes.light }
        if schemes.dark != baseDark { appearance.colorSchemeDark = schemes.dark }

        for key in Self.appearanceKeys {
            /// 鼠须管先看配色里的，再看全局 style；补丁优先于包里的 squirrel.yaml
            func value(_ layers: [PatchLeaves], scheme: String?) -> Node? {
                if let scheme {
                    for layer in layers { if let v = layer["preset_color_schemes/\(scheme)/\(key)"] { return v } }
                    if let v = file?["preset_color_schemes"]?[scheme]?[key] { return v }
                }
                for layer in layers { if let v = layer["style/\(key)"] { return v } }
                return file?["style"]?[key]
            }
            func changed(_ now: Node?, _ before: Node?) -> Bool {
                guard let now else { return false }
                return before.map { !YAMLNode.same($0, now) } ?? true
            }
            let light = value([mine, base], scheme: schemes.light)
            let dark = value([mine, base], scheme: schemes.dark)
            let lightChanged = changed(light, value([base], scheme: baseLight))
            let darkChanged = changed(dark, value([base], scheme: baseDark))
            guard lightChanged || darkChanged, let picked = lightChanged ? light : dark else { continue }
            if let light, let dark, !YAMLNode.same(light, dark) {
                notes.append("浅色和深色配色的 \(key) 不一样（\(light.string ?? "")、\(dark.string ?? "")），接管后都用 \(picked.string ?? "")")
            }
            if !set(&appearance, key, picked) {
                notes.append("认不出 \(key) 的值「\(picked.string ?? "")」，接管后用方案默认值")
            }
        }

        if let size = PatchLeaves(existing["default"] ?? Patch())["menu/page_size"] {
            let before = try PatchLeaves(expected["default"] ?? Patch())["menu/page_size"]
                ?? upstreamYAML("default.yaml")?["menu"]?["page_size"]
            if before.map({ !YAMLNode.same($0, size) }) ?? true {
                if let n = Int(size.string ?? ""), Settings.pageSizeRange.contains(n) {
                    appearance.pageSize = n
                } else {
                    notes.append("认不出每页候选数「\(size.string ?? "")」，接管后用方案默认值")
                }
            }
        }
        return appearance
    }

    /// 写进设置；值认不出或超出范围时返回 false
    func set(_ appearance: inout Appearance, _ key: String, _ value: Node) -> Bool {
        let text = value.string ?? ""
        switch key {
        case "font_point", "label_font_point", "comment_font_point":
            guard let n = Int(text), Settings.fontPointRange.contains(n) else { return false }
            if key == "font_point" { appearance.fontPoint = n }
            if key == "label_font_point" { appearance.labelFontPoint = n }
            if key == "comment_font_point" { appearance.commentFontPoint = n }
        case "candidate_list_layout":
            guard let v = CandidateListLayout(rawValue: text) else { return false }
            appearance.candidateListLayout = v
        case "text_orientation":
            guard let v = TextOrientation(rawValue: text) else { return false }
            appearance.textOrientation = v
        default:
            return false
        }
        return true
    }

    // MARK: 保留的补丁（规则 3、4）

    /// 应用管理的键：生成时由设置写出
    func managedPaths(_ name: String) -> [String] {
        switch name {
        case "default":
            return ["schema_list", "schema_list/+", "menu/page_size"]
        case "squirrel":
            var paths = ["style/color_scheme", "style/color_scheme_dark"] + Self.appearanceKeys.map { "style/\($0)" }
            for scheme in [schemes.light, schemes.dark].compactMap({ $0 }) {
                paths += Self.appearanceKeys.map { "preset_color_schemes/\(scheme)/\($0)" }
            }
            return paths
        default:
            // 方案自己的每页候选数会盖过应用里的设置（写在 default 里）：接管后改用应用的
            return survey.schemas.contains(name) ? ["menu/page_size"] : []
        }
    }

    /// 应用注入短语翻译器的两项：有短语时生成器会再写。
    /// 用户自己写了不一样的 custom_phrase 配置（例如用别的短语文件）时，两项都不算，原样保留
    func isPhraseInjection(_ entry: Patch.Entry, in patch: Patch) -> Bool {
        switch entry.key {
        case "engine/translators/@before 0":
            let ownConfig = patch["custom_phrase"].map { !YAMLNode.same($0, GenerationContext.phraseConfig()) } ?? false
            return entry.value.string == Self.phraseTranslator && !ownConfig
        case "custom_phrase": return YAMLNode.same(entry.value, GenerationContext.phraseConfig())
        default: return false
        }
    }

    func preservedItems(_ name: String) throws -> [PreservedPatch] {
        guard let mine = existing[name] else { return [] }
        let base = expected[name] ?? Patch()
        let baseLeaves = PatchLeaves(base)
        let managed = managedPaths(name)
        var entries = mine.entries.filter { !isPhraseInjection($0, in: mine) }
        // 值是空的项（「key:」）保存后读回来就没了：不保留，告诉用户
        for entry in entries where entry.value.null != nil {
            notes.append("\(name).custom.yaml 里 \(entry.key) 的值是空的，接管后不保留")
        }
        entries.removeAll { $0.value.null != nil }
        if survey.schemas.contains(name), PatchLeaves(mine)["menu/page_size"] != nil {
            notes.append("\(name).custom.yaml 里方案自己的每页候选数（menu/page_size）接管后改用应用里的设置")
        }

        // 和默认补丁、应用管理的键有上下级关系的项（以及和这些项有关系的项）逐个叶子比；其余整项原样保留
        var anchors = base.entries.map(\.key) + managed
        var related = Set<String>()
        var grew = true
        while grew {
            grew = false
            for entry in entries where !related.contains(entry.key) && anchors.contains(where: { PatchLeaves.overlaps($0, entry.key) }) {
                related.insert(entry.key)
                anchors.append(entry.key)
                grew = true
            }
        }
        var items: [PreservedPatch] = []
        for entry in entries where !related.contains(entry.key) {
            items.append(try Self.preserved(entry.key, entry.value))
        }
        var leaves = PatchLeaves()
        for entry in entries where related.contains(entry.key) { leaves.set(entry.key, entry.value) }
        for path in leaves.paths {
            let leaf = leaves[path]!
            if managed.contains(path) { continue }
            if let b = baseLeaves[path], YAMLNode.same(b, leaf) { continue }
            items.append(try Self.preserved(path, leaf))
        }

        let all = PatchLeaves(mine)
        let missing = baseLeaves.paths.filter { all[$0] == nil && !managed.contains($0) }
        if !missing.isEmpty {
            notes.append("\(name).custom.yaml 里没有上游默认补丁的这些项，接管后会按上游默认加上：\(missing.joined(separator: "、"))")
        }
        return items
    }

    static func preserved(_ key: String, _ value: Node) throws -> PreservedPatch {
        PreservedPatch(key: key, yaml: try Yams.serialize(node: value, allowUnicode: true))
    }

    // MARK: 短语（规则 7）

    func detectPhrases() throws -> (manual: [Phrase], matches: Int) {
        var phraseFiles: [String] = []
        for schema in survey.schemas {
            guard let root = try upstreamYAML("\(schema).schema.yaml") else { continue }
            let translators = root["engine"]?["translators"]?.sequence?.compactMap(\.string) ?? []
            // 方案本身没有短语翻译器、用户补丁里也没加：这个方案不用短语文件（目录里的多半是别的方案留下的）
            let injected = (existing[schema]?.entries ?? []).contains { entry in
                entry.key.hasPrefix("engine/translators")
                    && (entry.value.string == Self.phraseTranslator
                        || entry.value.sequence?.contains { $0.string == Self.phraseTranslator } == true)
            }
            guard translators.contains(Self.phraseTranslator) || injected else { continue }
            let file = translators.contains(Self.phraseTranslator)
                ? (root["custom_phrase"]?["user_dict"]?.string ?? "custom_phrase") + ".txt"
                // 用户补丁里可能指定了别的短语文件
                : (PatchLeaves(existing[schema] ?? Patch())["custom_phrase/user_dict"]?.string ?? "custom_phrase") + ".txt"
            if !phraseFiles.contains(file) { phraseFiles.append(file) }
        }
        let fromTextReplacement = Set(textReplacement.map { $0.text + "\t" + $0.code })
        var manual: [Phrase] = []
        var seen = Set<String>()
        var matched = Set<String>()
        for file in phraseFiles {
            guard files.contains(file), let text = try TakeoverFiles.read(rime, file) else { continue }
            var upstream = Set<String>()
            if let url = upstreamURL(file) {
                upstream = Set(PhraseFile.parse(try TextFile.read(url)).map { $0.text + "\t" + $0.code })
            }
            for phrase in PhraseFile.parse(text) {
                let key = phrase.text + "\t" + phrase.code
                if upstream.contains(key) { continue }
                if fromTextReplacement.contains(key) {
                    matched.insert(key)
                    continue
                }
                if seen.insert(phrase.line).inserted { manual.append(phrase) }
            }
        }
        return (manual, matched.count)
    }
}
