import Foundation
import RimeKit

/// rimectl：RimeKit 的命令行入口，用来在测试机里通过 SSH 跑完整流程
@main
struct Rimectl {
    struct Context: Sendable {
        var http: any HTTPClient
        var retry: RetryPolicy
        var catalog: @Sendable () throws -> Catalog
        var defaultPaths: AppPaths
        var output: Output
        var locations: RimeLocations = .default
        /// 空就用鼠须管自带的 rime_deployer
        var compiler: (any RimeCompiler)? = nil
        /// 空就控制真的鼠须管
        var squirrel: (any SquirrelControlling)? = nil
        var deployTimeout: Duration = .seconds(120)
        var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        /// 空就用真的 TIS
        var inputSource: (any InputSourceControlling)? = nil
        /// 空就按 --gui-auth 选系统授权框或免密 sudo
        var privileged: (any PrivilegedInstalling)? = nil
        /// 空就用真的三道检查
        var verifier: (any PackageVerifying)? = nil
        var activationTimeout: Double = 600
        /// 读 macOS 文本替换；测试时换成假的
        var textReplacements: @Sendable () throws -> [Phrase] = { try TextReplacementReader().read() }
    }

    static let usage = """
    用法：
      rimectl catalog                                          列出内置方案清单
      rimectl fetch [--cache-only] 包名...                      下载（或从缓存取）这些包和它们的依赖
      rimectl settings init <rime-ice|flypy|wubi-pinyin> [--force]   写入起步设置
      rimectl settings show                                    打印当前设置
      rimectl settings set <键> <值>                            改一项设置（键：schemas、font-point、label-font-point、
                                                               comment-font-point、page-size、layout、orientation、
                                                               color-scheme、color-scheme-dark、option；值写 - 表示清空）
      rimectl generate --out 目录 [--cache-only]                按设置生成一份 Rime 配置（只往空目录写）
      rimectl apply [--cache-only] [--overwrite] [--adopt-personal]   把设置应用到 Rime 目录并通知鼠须管部署
      rimectl takeover [--confirm] [--force] [--cache-only]    认出已有的 Rime 配置并预览；加 --confirm 才真的接管（先完整备份）
      rimectl status                                           查看鼠须管、Rime 目录、外部改动、备份
      rimectl restore --list | <备份 id>                        列出备份 / 还原到某个备份
      rimectl install [--force] [--gui-auth]                   下载、检查、安装鼠须管（--gui-auth 弹系统授权框，否则用免密 sudo）
      rimectl activate [--timeout 秒]                           打开系统设置等你添加鼠须管，然后切换过去并启动它
      rimectl doctor [--offline]                               检查环境，告诉你下一步做什么
    通用参数：--data-dir 目录（应用数据目录）  --rime-dir 目录（Rime 用户目录，默认 ~/Library/Rime）
    """

    static func main() async {
        let context = Context(
            http: URLSessionHTTPClient(),
            retry: .standard,
            catalog: { try Catalog.builtIn() },
            defaultPaths: .default,
            output: Output(echo: true))
        exit(await run(Array(CommandLine.arguments.dropFirst()), context))
    }

    static func run(_ args: [String], _ context: Context) async -> Int32 {
        let out = context.output
        var dataDir: String?
        var cacheOnly = false
        var outDir: String?
        var force = false
        var rimeDir: String?
        var overwrite = false
        var adoptPersonal = false
        var listOnly = false
        var guiAuth = false
        var offline = false
        var timeout: Double?
        var confirm = false
        var positional: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--data-dir":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                dataDir = args[i + 1]
                i += 2
            case "--out":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                outDir = args[i + 1]
                i += 2
            case "--rime-dir":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                rimeDir = args[i + 1]
                i += 2
            case "--overwrite":
                overwrite = true
                i += 1
            case "--adopt-personal":
                adoptPersonal = true
                i += 1
            case "--gui-auth":
                guiAuth = true
                i += 1
            case "--offline":
                offline = true
                i += 1
            case "--timeout":
                guard i + 1 < args.count, let seconds = Double(args[i + 1]) else { out.error(usage); return 2 }
                timeout = seconds
                i += 2
            case "--confirm":
                confirm = true
                i += 1
            case "--list":
                listOnly = true
                i += 1
            case "--force":
                force = true
                i += 1
            case "--cache-only":
                cacheOnly = true
                i += 1
            case "-h", "--help":
                out.line(usage)
                return 0
            default:
                positional.append(args[i])
                i += 1
            }
        }
        guard let command = positional.first else { out.error(usage); return 2 }
        let paths = dataDir.map { AppPaths(root: URL(fileURLWithPath: $0, isDirectory: true)) } ?? context.defaultPaths
        var locations = context.locations
        if let rimeDir { locations.rimeDirectory = URL(fileURLWithPath: rimeDir, isDirectory: true) }

        do {
            switch command {
            case "catalog":
                try listCatalog(try context.catalog(), out)
                return 0
            case "settings":
                return try settingsCommand(Array(positional.dropFirst()), force: force, paths: paths, context)
            case "generate":
                guard let outDir else { out.error(usage); return 2 }
                return try await generate(out: URL(fileURLWithPath: outDir, isDirectory: true),
                                          cacheOnly: cacheOnly, paths: paths, context)
            case "apply":
                return try await apply(cacheOnly: cacheOnly,
                                       options: ApplyOptions(overwriteExternalChanges: overwrite, adoptPersonalChanges: adoptPersonal),
                                       paths: paths, locations: locations, context)
            case "takeover":
                return try await takeover(confirm: confirm, force: force, cacheOnly: cacheOnly,
                                          paths: paths, locations: locations, context)
            case "status":
                return try status(paths: paths, locations: locations, context)
            case "restore":
                return try await restore(Array(positional.dropFirst()), listOnly: listOnly,
                                         paths: paths, locations: locations, context)
            case "install":
                return try await install(force: force, guiAuth: guiAuth, paths: paths, locations: locations, context)
            case "activate":
                return try await activate(timeout: timeout ?? context.activationTimeout, locations: locations, context)
            case "doctor":
                return await doctor(offline: offline, paths: paths, locations: locations, context)
            case "fetch":
                let ids = Array(positional.dropFirst())
                guard !ids.isEmpty else { out.error(usage); return 2 }
                return try await fetch(ids, cacheOnly: cacheOnly, paths: paths, context)
            default:
                out.error(usage)
                return 2
            }
        } catch {
            out.error(String(describing: error))
            return 1
        }
    }

    private static func listCatalog(_ catalog: Catalog, _ out: Output) throws {
        for p in catalog.packages {
            out.line("\(p.id)  \(p.name)  \(p.license)")
            for s in p.schemas {
                out.line("  - \(s.id)  \(s.name)")
            }
        }
    }

    /// 取一个包：cacheOnly 时只用本地缓存；下载失败时提示可以用旧版本。失败返回 nil（已经输出了错误）。
    private static func obtain(_ spec: PackageSpec, cacheOnly: Bool, store: PackageStore, _ out: Output) async throws -> CachedPackage? {
        if cacheOnly {
            guard let pkg = store.latestCached(for: spec) else {
                out.error("\(spec.id)：本地没有缓存")
                return nil
            }
            return pkg
        }
        do {
            return try await store.fetch(spec)
        } catch where PackageStore.isDownloadFailure(error) {
            var message = "\(spec.id)：下载失败。\(error)"
            if let old = store.latestCached(for: spec) {
                message += "\n本地有缓存的旧版本 \(old.info.version)，可以加 --cache-only 先用它"
            }
            out.error(message)
            return nil
        }
    }

    private static func fetch(_ ids: [String], cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        let catalog = try context.catalog()
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        for spec in try catalog.installOrder(for: ids) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            report(pkg, out)
        }
        return 0
    }

    private static func settingsCommand(_ args: [String], force: Bool, paths: AppPaths, _ context: Context) throws -> Int32 {
        let out = context.output
        let store = SettingsStore(paths: paths)
        switch args.first {
        case "init":
            guard args.count == 2, let starter = Starter(rawValue: args[1]) else { out.error(usage); return 2 }
            if try store.load() != nil, !force {
                out.error("已经有设置了：\(paths.settingsFile.path)。要覆盖就加 --force")
                return 1
            }
            let settings = Settings.starter(starter)
            try settings.validate(try context.catalog())
            try store.save(settings)
            out.line("已写入起步设置「\(starter.displayName)」：\(paths.settingsFile.path)")
            return 0
        case "set":
            guard args.count == 3 else { out.error(usage); return 2 }
            guard var settings = try store.load() else {
                out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
                return 1
            }
            guard applySetting(args[1], args[2], to: &settings) else { out.error(usage); return 2 }
            try settings.validate(try context.catalog())
            try store.save(settings)
            out.line("已更新 \(args[1])")
            return 0
        case "show":
            guard let settings = try store.load() else {
                out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
                return 1
            }
            out.line(String(decoding: try JSONCoding.encoder.encode(settings), as: UTF8.self))
            return 0
        default:
            out.error(usage)
            return 2
        }
    }

    /// 读设置、取包、读个人内容；失败时已经输出了错误，返回 nil
    private static func prepareInput(cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> GenerationInput? {
        let out = context.output
        guard let settings = try SettingsStore(paths: paths).load() else {
            out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
            return nil
        }
        let catalog = try context.catalog()
        try settings.validate(catalog)
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return nil }
            packages[spec.id] = pkg
        }
        let textReplacement = settings.textReplacement.sync ? try context.textReplacements() : []
        return GenerationInput(settings: settings, catalog: catalog, packages: packages,
                               personal: try PersonalContent.load(from: paths), textReplacementPhrases: textReplacement)
    }

    private static func generate(out target: URL, cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        if RimeDirectoryGuard.isInsideRealRimeDirectory(target) {
            out.error("拒绝：--out 指向真实的 ~/Library/Rime（\(target.path)）。generate 只往别的空目录里写")
            return 1
        }
        guard let input = try await prepareInput(cacheOnly: cacheOnly, paths: paths, context) else { return 1 }
        let result = try ConfigGenerator().generate(input, into: target)
        for warning in result.warnings { out.line("注意：\(warning)") }
        out.line("已生成 \(result.files.count) 个文件到 \(target.path)")
        return 0
    }

    private static func deployer(paths: AppPaths, locations: RimeLocations, _ context: Context) -> Deployer {
        Deployer(
            paths: paths,
            locations: locations,
            compiler: context.compiler ?? DeployerCompiler(locations: locations),
            squirrel: context.squirrel ?? SquirrelControl(locations: locations),
            watcher: DeployWatcher(locations: locations, timeout: context.deployTimeout, sleep: context.sleep))
    }

    private static func apply(cacheOnly: Bool, options: ApplyOptions, paths: AppPaths, locations: RimeLocations,
                              _ context: Context) async throws -> Int32 {
        let out = context.output
        guard let input = try await prepareInput(cacheOnly: cacheOnly, paths: paths, context) else { return 1 }
        return printApplyOutcome(try await deployer(paths: paths, locations: locations, context).apply(input, options: options), out)
    }

    private static func printApplyOutcome(_ outcome: ApplyOutcome, _ out: Output) -> Int32 {
        switch outcome {
        case .externalChanges(let changes):
            out.error("这些文件和应用记录的不一样，没有写入：")
            for change in changes { out.error("  \(change)") }
            out.error("要覆盖就加 --overwrite（会先备份）；被改过的个人词库可以加 --adopt-personal 采用外面的修改")
            return 1
        case .compileFailed(let errors):
            out.error("新配置编译不过，没有写入：")
            for error in errors { out.error("  \(error)") }
            return 1
        case .applied(let report):
            out.line("已备份：\(report.backup.id)（\(report.backup.reason)\(report.backup.permanent ? "，这份永久保留" : "")）")
            out.line("写入 \(report.written.count) 个文件，没变 \(report.unchanged) 个，删掉 \(report.removed.count) 个")
            for warning in report.warnings { out.line("注意：\(warning)") }
            out.line(report.launched ? "已启动鼠须管" : "已通知鼠须管重新部署")
            return reportDeploy(report.deploy, backupID: report.backup.id, out)
        }
    }

    private static func takeover(confirm: Bool, force: Bool, cacheOnly: Bool, paths: AppPaths, locations: RimeLocations,
                                 _ context: Context) async throws -> Int32 {
        let out = context.output
        guard try Ledger.load(paths).entries.isEmpty else {
            out.error(TakeoverError.alreadyManaged.description)
            return 1
        }
        if FileManager.default.fileExists(atPath: paths.settingsFile.path), !force {
            out.error(TakeoverError.settingsExist(paths.settingsFile.path).description)
            return 1
        }
        let catalog = try context.catalog()
        let rime = locations.rimeDirectory
        let survey = try TakeoverSurvey.scan(rime, catalog: catalog)
        if survey.isEmpty {
            out.line("Rime 目录里没有配置，不用接管。先选一个起步方案：rimectl settings init rime-ice|flypy|wubi-pinyin，再 rimectl apply")
            return 0
        }
        guard !survey.schemas.isEmpty else {
            out.error(TakeoverError.nothingRecognized.description)
            return 1
        }
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try catalog.installOrder(for: survey.packages) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        var textReplacement: [Phrase] = []
        var textReplacementError: (any Error)?
        do {
            textReplacement = try context.textReplacements()
        } catch {
            textReplacementError = error
            out.line("注意：\(error)。下面的短语都算成了手动短语，里面可能有文本替换的内容")
        }
        let proposal = try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: packages,
                                                    textReplacement: textReplacement)
        for spec in try proposal.settings.requiredPackages(catalog) where packages[spec.id] == nil {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        let preview = try TakeoverPreview.make(proposal, rime: rime, catalog: catalog, packages: packages,
                                               textReplacement: textReplacement, staging: paths.staging)
        printTakeover(proposal, preview, catalog: catalog, rime: rime, out)
        guard confirm else {
            out.line("这只是预览，什么都没改。确认接管：rimectl takeover --confirm（会先完整备份 Rime 目录，这份备份永久保留）")
            return 0
        }
        if let textReplacementError {
            // 分不出哪些短语来自文本替换：接管会把它们存成手动短语，以后还会被导出（设计：文本替换默认不导出）
            out.error("读不了 macOS 文本替换（\(textReplacementError)），分不出哪些短语来自文本替换，没有接管。解决后再运行 rimectl takeover --confirm")
            return 1
        }
        let outcome = try await TakeoverApplier(deployer: deployer(paths: paths, locations: locations, context))
            .confirm(proposal, catalog: catalog, packages: packages, textReplacement: textReplacement, force: force)
        return printApplyOutcome(outcome, out)
    }

    /// 只打印设置、文件名和条数，不打印词库和短语的内容
    private static func printTakeover(_ proposal: TakeoverProposal, _ preview: TakeoverPreview, catalog: Catalog,
                                      rime: URL, _ out: Output) {
        let s = proposal.settings
        func schemaName(_ id: String) -> String {
            let name = catalog.packageOwning(schema: id)?.schemas.first { $0.id == id }?.name ?? id
            return "\(name)（\(id)）"
        }
        out.line("Rime 目录：\(rime.path)")
        out.line("方案（第一个是默认方案）：" + s.schemas.map(schemaName).joined(separator: "、"))
        for packageID in s.options.keys.sorted() {
            guard let spec = catalog.package(packageID) else { continue }
            for option in spec.options {
                out.line("选项：\(spec.name) · \(option.name)：\(s.choice(option, of: spec).name)")
            }
        }
        let a = s.appearance
        var look: [String] = []
        if let v = a.fontPoint { look.append("候选字字号 \(v)") }
        if let v = a.labelFontPoint { look.append("序号字号 \(v)") }
        if let v = a.commentFontPoint { look.append("注释字号 \(v)") }
        if let v = a.colorScheme { look.append("浅色配色 \(v)") }
        if let v = a.colorSchemeDark { look.append("深色配色 \(v)") }
        if let v = a.candidateListLayout { look.append(v == .linear ? "候选横排" : "候选竖排") }
        if let v = a.textOrientation { look.append(v == .horizontal ? "文字横排" : "文字竖排") }
        if let v = a.pageSize { look.append("每页 \(v) 个候选") }
        out.line("外观：" + (look.isEmpty ? "都是方案默认的" : look.joined(separator: "，")))
        for (name, items) in s.preservedPatches.sorted(by: { $0.key < $1.key }) {
            out.line("保留的补丁：\(name).custom.yaml 里的 " + items.map(\.key).joined(separator: "、"))
        }
        let dicts = proposal.personalDicts.map(\.lastPathComponent)
        out.line("个人词库：\(dicts.count) 个" + (dicts.isEmpty ? "" : "（\(dicts.joined(separator: "、"))）"))
        out.line("手动短语：\(proposal.manualPhrases.count) 条")
        if proposal.textReplacementMatches > 0 {
            out.line("和 macOS 文本替换一样的短语：\(proposal.textReplacementMatches) 条（接管后打开文本替换同步，由它生成）")
        }
        for note in proposal.notes + preview.warnings { out.line("注意：\(note)") }
        out.line("接管后：换掉 \(preview.replaced.count) 个文件，内容不变 \(preview.unchanged.count) 个，新加 \(preview.added.count) 个，原样保留 \(preview.kept.count) 个")
        if !preview.replaced.isEmpty { out.line("  换掉：" + preview.replaced.joined(separator: "、")) }
        if !preview.added.isEmpty { out.line("  新加：" + preview.added.joined(separator: "、")) }
        if !preview.kept.isEmpty { out.line("  原样保留：" + preview.kept.joined(separator: "、")) }
    }

    private static func reportDeploy(_ deploy: DeployOutcome, backupID: String, _ out: Output) -> Int32 {
        guard deploy.finished else {
            out.error("等了很久还没看到部署完成。可以过一会儿用 rimectl status 再看；有问题可以 rimectl restore \(backupID)")
            return 1
        }
        guard deploy.errors.isEmpty else {
            out.error("部署完成，但有错误：")
            for error in deploy.errors { out.error("  \(error)") }
            out.error("想回到之前的样子：rimectl restore \(backupID)")
            return 1
        }
        out.line("部署完成")
        return 0
    }

    private static func status(paths: AppPaths, locations: RimeLocations, _ context: Context) throws -> Int32 {
        let out = context.output
        let s = try deployer(paths: paths, locations: locations, context).status()
        let squirrelText = s.squirrelInstalled ? (s.squirrelRunning ? "已安装，正在运行" : "已安装，没在运行") : "没安装"
        out.line("鼠须管：\(squirrelText)")
        out.line("Rime 目录：\(s.rimeDirectory.path)")
        let applied = s.appliedAt.map { "，上次应用：\($0.formatted(date: .numeric, time: .standard))" } ?? "，还没应用过"
        out.line("应用管理的文件：\(s.managedFiles) 个\(applied)")
        if s.externalChanges.isEmpty {
            out.line("外部改动：没有")
        } else {
            out.line("外部改动：")
            for change in s.externalChanges { out.line("  \(change)") }
        }
        out.line("备份：\(s.backups.count) 份" + (s.backups.first.map { "，最近一份 \($0.id)（\($0.reason)）" } ?? ""))
        return 0
    }

    private static func restore(_ args: [String], listOnly: Bool, paths: AppPaths, locations: RimeLocations,
                                _ context: Context) async throws -> Int32 {
        let out = context.output
        if listOnly {
            for b in BackupStore(paths: paths).list() {
                out.line("\(b.id)  \(b.reason)\(b.permanent ? "（永久保留）" : "")  \(b.files.count) 个文件")
            }
            return 0
        }
        guard args.count == 1 else { out.error(usage); return 2 }
        let report = try await deployer(paths: paths, locations: locations, context).restore(args[0])
        out.line("已还原到 \(report.restored.id)（\(report.restored.reason)）")
        out.line("还原前的状态也备份了：\(report.safetyBackup.id)")
        for warning in report.warnings { out.line("注意：\(warning)") }
        return reportDeploy(report.deploy, backupID: report.safetyBackup.id, out)
    }

    /// 改一项设置；键或值的格式不对返回 false
    private static func applySetting(_ key: String, _ value: String, to s: inout Settings) -> Bool {
        let clear = value == "-"
        func int() -> Int?? { clear ? .some(nil) : Int(value).map { .some($0) } }
        switch key {
        case "schemas":
            s.schemas = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case "font-point":
            guard let v = int() else { return false }
            s.appearance.fontPoint = v
        case "label-font-point":
            guard let v = int() else { return false }
            s.appearance.labelFontPoint = v
        case "comment-font-point":
            guard let v = int() else { return false }
            s.appearance.commentFontPoint = v
        case "page-size":
            guard let v = int() else { return false }
            s.appearance.pageSize = v
        case "layout":
            if clear { s.appearance.candidateListLayout = nil } else {
                guard let v = CandidateListLayout(rawValue: value) else { return false }
                s.appearance.candidateListLayout = v
            }
        case "orientation":
            if clear { s.appearance.textOrientation = nil } else {
                guard let v = TextOrientation(rawValue: value) else { return false }
                s.appearance.textOrientation = v
            }
        case "color-scheme":
            s.appearance.colorScheme = clear ? nil : value
        case "color-scheme-dark":
            s.appearance.colorSchemeDark = clear ? nil : value
        case "option":
            let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
            let head = parts.first?.split(separator: ".", maxSplits: 1).map(String.init) ?? []
            guard parts.count == 2, head.count == 2 else { return false }
            s.options[head[0], default: [:]][head[1]] = parts[1]
        default:
            return false
        }
        return true
    }

    private static func install(force: Bool, guiAuth: Bool, paths: AppPaths, locations: RimeLocations,
                                _ context: Context) async throws -> Int32 {
        let out = context.output
        let privileged: any PrivilegedInstalling = context.privileged
            ?? (guiAuth ? AuthorizationPromptInstaller() : SudoPackageInstaller())
        let installer = SquirrelInstaller(paths: paths, locations: locations, http: context.http, retry: context.retry,
                                          verifier: context.verifier ?? SquirrelPackageVerifier(), privileged: privileged)
        out.line("正在检查鼠须管的最新版本……")
        switch try await installer.install(force: force) {
        case .alreadyInstalled(let version):
            out.line("已经装了鼠须管 \(version)，是最新的，不用装")
        case let .installed(version, previous):
            out.line(previous.map { "已安装鼠须管 \(version)（原来是 \($0)）" } ?? "已安装鼠须管 \(version)")
            out.line("下一步：运行 rimectl activate，在系统设置里添加鼠须管")
        }
        return 0
    }

    private static func activate(timeout: Double, locations: RimeLocations, _ context: Context) async throws -> Int32 {
        let out = context.output
        let activator = SquirrelActivator(
            locations: locations,
            inputSource: context.inputSource ?? TISInputSourceService(),
            squirrel: context.squirrel ?? SquirrelControl(locations: locations),
            watcher: DeployWatcher(locations: locations, timeout: context.deployTimeout, sleep: context.sleep),
            timeout: timeout)
        let outcome = try await activator.activate(onWaiting: {
            out.line("已打开系统设置的键盘页。请在「文字输入 → 输入法 → 编辑… → + → 简体中文 → 鼠须管」里添加，")
            out.line("添加好后这里会自动继续（最多等 \(Int(timeout)) 秒）……")
        })
        switch outcome {
        case let .ready(_, launched):
            if launched { out.line("已启动鼠须管") }
            out.line("鼠须管可以用了")
            return 0
        case .timedOut:
            out.error("等了 \(Int(timeout)) 秒，还没看到鼠须管被添加。添加好后再运行一次 rimectl activate")
            return 1
        case .notRegistered:
            out.error("系统里没有鼠须管的输入源，可能没装好。请运行 rimectl install --force 重新安装")
            return 1
        }
    }

    private static func doctor(offline: Bool, paths: AppPaths, locations: RimeLocations, _ context: Context) async -> Int32 {
        let out = context.output
        let doctor = Doctor(
            paths: paths, locations: locations,
            inputSource: context.inputSource ?? TISInputSourceService(),
            squirrel: context.squirrel ?? SquirrelControl(locations: locations),
            releaseSource: offline ? nil : SquirrelReleaseSource(http: context.http, retry: context.retry))
        let checks = await doctor.run()
        for check in checks {
            let mark = switch check.level {
            case .ok: "[正常]"
            case .warning: "[注意]"
            case .problem: "[问题]"
            }
            out.line("\(mark) \(check.name)：\(check.message)")
            if let hint = check.hint { out.line("       → \(hint)") }
        }
        return checks.contains { $0.level == .problem } ? 1 : 0
    }

    private static func report(_ pkg: CachedPackage, _ out: Output) {
        out.line("\(pkg.info.id)@\(pkg.info.version)  \(pkg.info.files.count) 个文件  \(pkg.filesDirectory.path)")
    }
}
