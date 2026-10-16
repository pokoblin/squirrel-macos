import Foundation
import RimeKit

extension Rimectl {
    /// 五笔个人词库（设计 4.7）。add、import、remove 只写 personal/，不自动应用
    static func wubi(_ args: [String], position: Int?, paths: AppPaths, locations: RimeLocations,
                     _ context: Context) async -> Int32 {
        let out = context.output
        let target = WubiDictTarget.jidian
        guard let command = args.first else { out.error(usage); return 2 }
        let rest = Array(args.dropFirst())
        // 先查参数，别白白读词库
        switch command {
        case "encode": guard !rest.isEmpty else { out.error(usage); return 2 }
        case "list", "check": guard rest.isEmpty else { out.error(usage); return 2 }
        case "add": guard (1...2).contains(rest.count) else { out.error(usage); return 2 }
        case "remove": guard (1...2).contains(rest.count) else { out.error(usage); return 2 }
        case "import": guard rest.count == 1 else { out.error(usage); return 2 }
        default: out.error(usage); return 2
        }
        if position != nil, command != "add" { out.error(usage); return 2 }

        do {
            let settings = try SettingsStore(paths: paths).load()
            guard let settings, WubiCheck.checkSchema(in: settings, target: target) != nil else {
                out.error("先在「方案」页启用极点五笔")
                return 1
            }
            let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
            guard let package = store.latestCached(target.packageID) else {
                out.error("还没下载极点五笔，先应用一次改动")
                return 1
            }
            let userDict = WubiUserDict(paths: paths, locations: locations, target: target)
            // 个人词库读不了时，encode 不需要它，其余命令抛出原因
            let loaded = Result { try userDict.load(package: package) }
            if command == "encode" {
                let editor = try WubiEditor(package: package, userFile: (try? loaded.get()) ?? DictFile.parse("---\n...\n"))
                return encode(rest, editor, out)
            }
            let editor = try WubiEditor(package: package, userFile: try loaded.get())
            let env = WubiEnvironment(userDict: userDict, editor: editor)

            switch command {
            case "list":
                return list(env, out)
            case "add":
                return try add(rest[0], code: rest.count > 1 ? rest[1] : nil, position: position, env, out)
            case "remove":
                return try remove(rest[0], code: rest.count > 1 ? rest[1] : nil, env, out)
            case "import":
                return try importWords(from: rest[0], env, out)
            default:
                return try await check(settings: settings, env: env, paths: paths, locations: locations, context)
            }
        } catch let error as PreviewError {
            out.error(error.description)
            return 1
        } catch {
            out.error(String(describing: error))
            return 1
        }
    }

    private struct WubiEnvironment {
        let userDict: WubiUserDict
        let editor: WubiEditor
    }

    private static let applyHint = "运行 rimectl apply 让它生效"

    // MARK: encode

    private static func encode(_ words: [String], _ editor: WubiEditor, _ out: Output) -> Int32 {
        guard let encoder = editor.encoder else {
            out.error(WubiEditProblem.noEncoder.description)
            return 1
        }
        for word in words {
            switch encoder.encode(word) {
            case .codes(let list):
                out.line("\(word)\t\(list.joined(separator: " "))")
            case .unknown(let chars) where chars.isEmpty:
                out.line("\(word)\t算不出")
            case .unknown(let chars):
                out.line("\(word)\t算不出：\(chars.map(String.init).joined(separator: "、"))")
            case .singleCharacter:
                out.line("\(word)\t算不出：单字要手动填编码")
            }
        }
        return 0
    }

    // MARK: list

    private static func list(_ env: WubiEnvironment, _ out: Output) -> Int32 {
        let file = env.editor.userFile
        for entry in file.entries {
            let weight = entry.weight.map(String.init) ?? "-"
            if let code = entry.code, !code.isEmpty {
                out.line("\(entry.text)\t\(code)\t\(weight)")
            } else if let code = env.editor.autoCode(entry.text) {
                out.line("\(entry.text)\t\(code)（自动）\t\(weight)")
            } else {
                out.line("\(entry.text)\t算不出\t\(weight)")
            }
        }
        out.line("共 \(file.entries.count) 个")
        return 0
    }

    // MARK: add

    private static func add(_ word: String, code given: String?, position: Int?, _ env: WubiEnvironment,
                            _ out: Output) throws -> Int32 {
        guard !word.isEmpty else { out.error(usage); return 2 }
        let editor = env.editor
        let code: String
        switch editor.resolveCode(text: word, given: given) {
        case .success(let codes): code = codes[0]
        case .failure(let problem):
            out.error(problem.description)
            return 1
        }
        let entry: DictEntry
        switch editor.plan(text: word, code: code, position: position) {
        case .success(let planned): entry = planned
        case .failure(let problem):
            out.error(problem.description)
            return 1
        }
        let updated = editor.applying([entry])
        try env.userDict.save(updated.userFile)
        // 排第几以保存以后的顺序为准
        let place = updated.position(of: entry) ?? 1
        out.line("已加入：\(word) \(code)（排第 \(place) 个）")
        out.line(applyHint)
        return 0
    }

    // MARK: remove

    private static func remove(_ word: String, code: String?, _ env: WubiEnvironment, _ out: Output) throws -> Int32 {
        let matches = env.editor.removeMatches(text: word, code: code)
        guard !matches.isEmpty else {
            out.error("没找到这个词")
            return 1
        }
        try env.userDict.save(WubiEditor.remove(indices: matches, from: env.editor.userFile))
        out.line("删掉 \(matches.count) 条")
        out.line(applyHint)
        return 0
    }

    // MARK: import

    private static func importWords(from path: String, _ env: WubiEnvironment, _ out: Output) throws -> Int32 {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            out.error("读不了文件（要 UTF-8 文本）：\(path)")
            return 1
        }
        let rows = env.editor.parseImport(text)
        let entries = WubiImport.entries(from: rows)
        if !entries.isEmpty { try env.userDict.save(env.editor.applying(entries).userFile) }
        out.line("加入 \(entries.count) 个")
        for row in rows where !(row.selected && !row.text.isEmpty && WubiEncoder.isValidCode(row.code)) {
            out.line("第 \(row.id) 行：\(reason(row))")
        }
        if !entries.isEmpty { out.line(applyHint) }
        return 0
    }

    private static func reason(_ row: ImportRow) -> String {
        switch row.status {
        case .alreadyPersonal: return "已经加过了"
        case .alreadyInDict: return "词库里已经有了"
        case .duplicateInBatch: return "和前面的行重复"
        case .ok, .choose, .needsCode:
            if row.text.isEmpty { return "没有词" }
            if row.code.isEmpty { return "算不出编码" }
            if !WubiEncoder.isValidCode(row.code) { return "编码不合法" }
            return "这一行写得不对（权重要是整数，多出来的列不认识）"
        }
    }

    // MARK: check

    /// 检查个人词库里所有的词能不能打出来（设计 4.6）：在「应用后的样子」副本上试打，用完删掉副本
    private static func check(settings: Settings, env: WubiEnvironment, paths: AppPaths, locations: RimeLocations,
                              _ context: Context) async throws -> Int32 {
        let out = context.output
        let editor = env.editor
        guard let schema = WubiCheck.checkSchema(in: settings, target: editor.target) else { return 1 }
        // 没写编码的用自动算的第一个编码检查；算不出的没有编码可打
        let entries = editor.entriesWithCodes
        guard !entries.isEmpty else {
            out.line("个人词库里还没有词")
            return 0
        }

        var copy: PreviewCopy?
        defer { copy?.remove() }
        guard let input = try await prepareInput(cacheOnly: true, paths: paths, context) else { return 1 }
        let workspace = PreviewWorkspace(paths: paths, locations: locations,
                                         compiler: context.compiler ?? DeployerCompiler(locations: locations))
        copy = try workspace.preparePending(input)
        guard let copy else { return 1 }
        guard copy.schemas.contains(where: { $0.id == schema }) else {
            out.error("没有方案「\(schema)」。可以试打的方案：" + copy.schemas.map(\.id).joined(separator: "、"))
            return 1
        }
        guard let helper = context.previewHelper ?? PreviewHelperLocator.locate() else {
            out.error(PreviewError.helperMissing.description)
            return 1
        }
        let session = PreviewSession(helper: helper, squirrelApp: locations.squirrelApp)
        let results: [CheckResult]
        do {
            results = try await WubiCheck.run(entries, index: editor.index, engine: session, userDir: copy.userDir, schema: schema)
            await session.close()
        } catch {
            await session.close()
            throw error
        }

        var missing = 0
        for (entry, result) in zip(entries, results) {
            let code = entry.code ?? "算不出"
            switch result {
            case .asExpected(let page, let i):
                out.line("\(entry.text)\t\(code)\t第 \(page + 1) 页第 \(i + 1) 个")
            case .elsewhere(let page, let i):
                out.line("\(entry.text)\t\(code)\t位置和选的不一样：第 \(page + 1) 页第 \(i + 1) 个")
            case .missing:
                missing += 1
                out.line("\(entry.text)\t\(code)\t打不出来")
            }
        }
        return missing > 0 ? 1 : 0
    }
}
