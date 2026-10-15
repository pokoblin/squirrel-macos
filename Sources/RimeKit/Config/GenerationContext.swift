import Foundation
import Yams

/// 一次生成的过程和中间状态
final class GenerationContext {
    let input: GenerationInput
    let output: URL
    let required: [PackageSpec]
    private let fm = FileManager.default
    private var files: [String: FileOrigin] = [:]
    private(set) var warnings: [String] = []
    /// 配置名（default、squirrel、方案 id）→ 补丁
    var patches: [String: Patch] = [:]

    init(input: GenerationInput, output: URL) throws {
        self.input = input
        self.output = output
        if fm.fileExists(atPath: output.path) {
            guard try fm.contentsOfDirectory(atPath: output.path).isEmpty else {
                throw GenerationError.outputNotEmpty(output.path)
            }
        }
        required = try input.settings.requiredPackages(input.catalog)
        for spec in required where input.packages[spec.id] == nil {
            throw GenerationError.missingPackage(spec.id)
        }
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
    }

    func result() -> GenerationResult {
        GenerationResult(
            files: files.keys.sorted().map { GeneratedFile(path: $0, origin: files[$0]!) },
            warnings: warnings)
    }

    // MARK: 写文件

    func write(_ text: String, to path: String, origin: FileOrigin) throws {
        let url = output.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        files[path] = origin
    }

    func copy(_ source: URL, to path: String, origin: FileOrigin) throws {
        let target = output.appending(path: path)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
        files[path] = origin
    }

    func readYAML(_ path: String, label: String) throws -> Node? {
        let url = output.appending(path: path)
        guard fm.fileExists(atPath: url.path) else { return nil }
        do {
            return try YAMLNode.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw GenerationError.badYAML(file: label, message: String(describing: error))
        }
    }

    // MARK: 规则 2：复制上游文件

    static func isUpstreamPatch(_ path: String) -> Bool {
        !path.contains("/") && path.hasSuffix(".custom.yaml")
    }

    func copyPackageFiles() throws {
        for spec in required {
            let package = input.packages[spec.id]!
            for path in package.info.files where !Self.isUpstreamPatch(path) && path != "LICENSE" {
                let source = package.filesDirectory.appending(path: path)
                let target = output.appending(path: path)
                if fm.fileExists(atPath: target.path), !fm.contentsEqual(atPath: source.path, andPath: target.path) {
                    warnings.append("\(path) 在好几个包里都有而且内容不一样，用的是 \(spec.id) 的")
                }
                try copy(source, to: path, origin: .package(spec.id))
            }
        }
    }

    // MARK: 规则 3：上游补丁当默认值

    func collectUpstreamPatches() throws {
        for spec in required {
            let package = input.packages[spec.id]!
            for path in package.info.files where Self.isUpstreamPatch(path) {
                let name = String(path.dropLast(".custom.yaml".count))
                let text = try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8)
                do {
                    patches[name, default: Patch()].merge(try Patch.parse(customYAML: text))
                } catch {
                    throw GenerationError.badYAML(file: "\(spec.id)/\(path)", message: String(describing: error))
                }
            }
        }
    }

    // MARK: 设置里保留的补丁

    func applyPreservedPatches() throws {
        for (name, items) in input.settings.preservedPatches.sorted(by: { $0.key < $1.key }) {
            for item in items {
                let node: Node?
                do {
                    node = try YAMLNode.parse(item.yaml)
                } catch {
                    throw GenerationError.badYAML(file: "settings.json 里保留的 \(name) 补丁 \(item.key)", message: String(describing: error))
                }
                if let node { patches[name, default: Patch()].set(item.key, node) }
            }
        }
    }

    // MARK: 规则 4：方案列表、每页候选数

    func applySchemaList() {
        let list = YAMLNode.list(input.settings.schemas.map { YAMLNode.map([("schema", YAMLNode.text($0))]) })
        patches["default", default: Patch()].set("schema_list", list)
        if let pageSize = input.settings.appearance.pageSize {
            patches["default", default: Patch()].set("menu/page_size", YAMLNode.int(pageSize))
        }
    }

    // MARK: 规则 4：外观

    func applyAppearance() throws {
        let a = input.settings.appearance
        var p = patches["squirrel"] ?? Patch()
        if let s = a.colorScheme { p.set("style/color_scheme", YAMLNode.text(s)) }
        if let s = a.colorSchemeDark { p.set("style/color_scheme_dark", YAMLNode.text(s)) }
        var values: [(String, Node)] = []
        if let v = a.fontPoint { values.append(("font_point", YAMLNode.int(v))) }
        if let v = a.labelFontPoint { values.append(("label_font_point", YAMLNode.int(v))) }
        if let v = a.commentFontPoint { values.append(("comment_font_point", YAMLNode.int(v))) }
        if let v = a.candidateListLayout { values.append(("candidate_list_layout", YAMLNode.text(v.rawValue))) }
        if let v = a.textOrientation { values.append(("text_orientation", YAMLNode.text(v.rawValue))) }
        if !values.isEmpty {
            let schemes = try effectiveColorSchemes(p)
            for (key, value) in values {
                p.set("style/\(key)", value)
                for scheme in schemes { p.set("preset_color_schemes/\(scheme)/\(key)", value) }
            }
        }
        if !p.isEmpty { patches["squirrel"] = p }
    }

    /// 实际生效的浅色、深色配色名（去重）：补丁里写的（设置里指定的已经写进补丁）> 包里的 squirrel.yaml 写的
    func effectiveColorSchemes(_ patch: Patch) throws -> [String] {
        let file = try readYAML("squirrel.yaml", label: "squirrel.yaml")
        var result: [String] = []
        for key in ["color_scheme", "color_scheme_dark"] {
            let name = patch["style/\(key)"]?.string
                ?? patch["style"]?[key]?.string
                ?? file?["style"]?[key]?.string
            if let name, !result.contains(name) { result.append(name) }
        }
        return result
    }

    // MARK: 规则 5：包选项

    func applyOptions() throws {
        let enabled = Set(input.settings.schemas)
        for spec in required {
            for option in spec.options {
                let choice = input.settings.choice(option, of: spec)
                for (schema, values) in choice.patches.sorted(by: { $0.key < $1.key }) where enabled.contains(schema) {
                    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                        patches[schema, default: Patch()].set(key, YAMLNode.text(value))
                    }
                }
                for dict in choice.generatedDicts {
                    try write(renderDict(dict), to: "\(dict.name).dict.yaml", origin: .generated)
                }
            }
        }
    }

    func renderDict(_ dict: GeneratedDict) -> String {
        let tables = dict.importTables
            .filter { !$0.onlyIfPersonal || input.personal.hasDict(named: $0.name) }
            .map { "  - \($0.name)\n" }
            .joined()
        return Patch.header
            + "---\n"
            + "name: \(dict.name)\n"
            + "version: \"squirrel-macos\"\n"
            + "sort: by_weight\n"
            + "import_tables:\n"
            + tables
            + "...\n"
    }

    // MARK: 规则 6：个人词库（和上游同名时用个人的）

    func copyPersonalDicts() throws {
        for url in input.personal.dicts {
            try copy(url, to: url.lastPathComponent, origin: .personal)
        }
    }

    // MARK: 规则 8：写出补丁文件

    func writePatches() throws {
        for (name, patch) in patches.sorted(by: { $0.key < $1.key }) where !patch.isEmpty {
            try write(try patch.renderCustomYAML(), to: "\(name).custom.yaml", origin: .generated)
        }
    }
}
