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
            let main = try DictFile.parse(data: Data(contentsOf: package.filesDirectory.appending(path: target.mainDict)))
            let encoder = try? WubiEncoder(mainDict: main)
            let env = WubiEnvironment(target: target, package: package, userDict: userDict, encoder: encoder)

            switch command {
            case "encode":
                return encode(rest, env, out)
            case "list":
                return try list(env, out)
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
        let target: WubiDictTarget
        let package: CachedPackage
        let userDict: WubiUserDict
        /// 主词库里没有组词规则时是 nil：自动编码用不了
        let encoder: WubiEncoder?

        /// 编码索引：个人词库用 personal/ 里的版本（有的话）
        func index() throws -> WubiCodeIndex {
            try WubiCodeIndex.load(from: package, personalUserDict: userDict.personalFile, target: target)
        }

        /// 自动算出来的第一个编码；算不出是 nil
        func autoCode(_ text: String) -> String? {
            guard let encoder, case .codes(let list) = encoder.encode(text) else { return nil }
            return list.first
        }
    }

    private static let noEncoderMessage = "认不出这个版本的极点五笔词库，自动编码用不了"
    private static let applyHint = "运行 rimectl apply 让它生效"

    // MARK: encode

    private static func encode(_ words: [String], _ env: WubiEnvironment, _ out: Output) -> Int32 {
        guard let encoder = env.encoder else {
            out.error(noEncoderMessage)
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

    private static func list(_ env: WubiEnvironment, _ out: Output) throws -> Int32 {
        let file = try env.userDict.load(package: env.package)
        for entry in file.entries {
            let weight = entry.weight.map(String.init) ?? "-"
            if let code = entry.code, !code.isEmpty {
                out.line("\(entry.text)\t\(code)\t\(weight)")
            } else if let code = env.autoCode(entry.text) {
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
        let code: String
        if let given {
            guard WubiEncoder.isValidCode(given) else {
                out.error("编码只能是 a–y 的小写字母，1 到 4 个")
                return 1
            }
            code = given
        } else {
            guard let encoder = env.encoder else {
                out.error(noEncoderMessage)
                return 1
            }
            switch encoder.encode(word) {
            case .codes(let list): code = list[0]
            case .singleCharacter:
                out.error("只有一个字的词要自己填编码")
                return 1
            case .unknown(let chars):
                out.error("算不出编码" + (chars.isEmpty ? "" : "（\(chars.map(String.init).joined(separator: "、"))）")
                          + "，请自己填编码")
                return 1
            }
        }

        var file = try env.userDict.load(package: env.package)
        if file.entries.contains(where: { $0.text == word && $0.code == code }) {
            out.error("已经加过了")
            return 1
        }
        let index = try env.index()
        let found = index.contains(text: word, code: code)
        if found.inPersonal {
            out.error("已经加过了")
            return 1
        }
        if found.inOthers {
            out.error("词库里已经有了")
            return 1
        }

        var weight: Int?
        if let position {
            switch index.weight(forPosition: position - 1, code: code) {
            case .weight(let w): weight = w
            case .noWeight: weight = nil
            case .noRoom:
                out.error("这个位置放不进去")
                return 1
            }
        }
        file.append(DictEntry(text: word, code: code, weight: weight))
        try env.userDict.save(file)

        // 排第几以保存以后重新读出来的顺序为准
        let after = try env.index().words(for: code)
        let place = after.firstIndex { $0.text == word && $0.isPersonal }.map { $0 + 1 } ?? after.count
        out.line("已加入：\(word) \(code)（排第 \(place) 个）")
        out.line(applyHint)
        return 0
    }

    // MARK: remove

    private static func remove(_ word: String, code: String?, _ env: WubiEnvironment, _ out: Output) throws -> Int32 {
        var file = try env.userDict.load(package: env.package)
        let before = file.entries.count
        file.removeEntries { $0.text == word && (code == nil || $0.code == code) }
        let removed = before - file.entries.count
        guard removed > 0 else {
            out.error("没找到这个词")
            return 1
        }
        try env.userDict.save(file)
        out.line("删掉 \(removed) 条")
        out.line(applyHint)
        return 0
    }

    // MARK: import

    private static func importWords(from path: String, _ env: WubiEnvironment, _ out: Output) throws -> Int32 {
        guard let encoder = env.encoder else {
            out.error(noEncoderMessage)
            return 1
        }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            out.error("读不了文件（要 UTF-8 文本）：\(path)")
            return 1
        }
        var file = try env.userDict.load(package: env.package)
        var rows = WubiImport.parse(text, encoder: encoder, index: try env.index())
        // 索引读的是 personal/ 里的文件；还没有这个文件时（起点来自别处）也要照文件里的词条查一遍
        let existing = Set(file.entries.compactMap { e in e.code.map { e.text + "\t" + $0 } })
        for i in rows.indices where rows[i].selected && existing.contains(rows[i].text + "\t" + rows[i].code) {
            rows[i].status = .alreadyPersonal
            rows[i].selected = false
        }
        let entries = WubiImport.entries(from: rows)
        for entry in entries { file.append(entry) }
        if !entries.isEmpty { try env.userDict.save(file) }
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
        guard let schema = WubiCheck.checkSchema(in: settings, target: env.target) else { return 1 }
        let file = try env.userDict.load(package: env.package)
        guard !file.entries.isEmpty else {
            out.line("个人词库里还没有词")
            return 0
        }
        // 没写编码的用自动算的第一个编码检查；算不出的没有编码可打
        let entries = file.entries.map { e -> DictEntry in
            var e = e
            if e.code?.isEmpty ?? true { e.code = env.autoCode(e.text) }
            return e
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
        // 索引不收没写编码的词；把自动算出的编码补上，放进副本里的临时文件再读，预期的位置才算得对
        var coded = file
        for (i, e) in entries.enumerated() where file.entries[i].code?.isEmpty ?? true && e.code != nil {
            coded.replaceEntry(at: i, with: e)
        }
        let codedFile = copy.root.appending(path: "check-\(env.target.userDict)")
        try Data(coded.render().utf8).write(to: codedFile)
        let index = try WubiCodeIndex.load(from: env.package, personalUserDict: codedFile, target: env.target)
        guard let helper = context.previewHelper ?? PreviewHelperLocator.locate() else {
            out.error(PreviewError.helperMissing.description)
            return 1
        }
        let session = PreviewSession(helper: helper, squirrelApp: locations.squirrelApp)
        let results: [CheckResult]
        do {
            results = try await WubiCheck.run(entries, index: index, engine: session, userDir: copy.userDir, schema: schema)
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
