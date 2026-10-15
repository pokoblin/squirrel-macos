import Foundation
import Observation
import RimeKit

public enum StartChoice: Sendable, Equatable {
    /// Rime 目录里没有配置：选起步方案，或者从导出文件导入
    case empty
    /// 有能认出来的配置：先看预览，用户确认后接管
    case existing(TakeoverSummary)
    /// 有配置但认不出方案：选起步方案（原来的文件先完整备份），或者导入
    case unrecognized
}

/// 第一次打开时的引导（设计 6.2）：装鼠须管 → 添加输入法 → 起步方案 / 接管 / 导入。
/// 只调用 RimeKit；界面按 step 显示，按钮调用对应的方法
@MainActor @Observable
public final class SetupFlow {
    public enum Step: Equatable {
        case checking
        case needInstall
        /// 附带说明（例如等超时了）
        case needInputMethod(String?)
        case waitingForInputMethod
        /// 重新注册了输入源：要退出应用再打开（同一个进程里 TIS 的状态不会更新）
        case needRestart
        case chooseStart(StartChoice)
        /// 正在做的事（下载、写入、部署……）
        case working(String)
        /// 完成，附带说明和提醒
        case done([String])
        case failed(String)
    }

    public private(set) var step: Step = .checking
    let env: AppEnvironment
    /// 预览过、可以接管的结果
    private var pendingTakeover: (proposal: TakeoverProposal, packages: [String: CachedPackage], textReplacement: [Phrase])?

    public init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: 开始

    public func start() async {
        step = .checking
        let managed = (try? Ledger.load(env.paths))?.entries.isEmpty == false
        if managed, (try? SettingsStore(paths: env.paths).load()) != nil {
            step = .done(["鼠须管已经由这个应用管理了"])
            return
        }
        guard env.locations.squirrelInstalled else {
            step = .needInstall
            return
        }
        let state = env.inputSource.state()
        guard state.registered, state.enabled else {
            step = .needInputMethod(nil)
            return
        }
        // 已经添加了但没选中：切换过去（设计 6.2）；切换失败不要紧，用户可以按切换键
        if !state.selected { try? env.inputSource.selectSquirrel() }
        await prepareStart()
    }

    // MARK: 第一步：安装鼠须管

    public func install() async {
        step = .working("正在下载、检查鼠须管的安装包。之后会弹出系统授权框，请输入这台 Mac 的登录密码……")
        do {
            let install = env.installSquirrel
            _ = try await offMain { try await install() }
            step = .needInputMethod(nil)
        } catch InstallError.cancelled {
            step = .failed("你取消了授权，鼠须管没有安装。准备好了再点「重试」")
        } catch {
            step = .failed("安装鼠须管失败：\(error)")
        }
    }

    // MARK: 第二步：添加输入法

    public func addInputMethod() async {
        step = .waitingForInputMethod
        let activator = SquirrelActivator(
            locations: env.locations, inputSource: env.inputSource, squirrel: env.squirrel,
            watcher: DeployWatcher(locations: env.locations, timeout: env.deployTimeout, sleep: env.sleep),
            timeout: env.activationTimeout)
        do {
            switch try await offMain({ try await activator.activate() }) {
            case .ready:
                await prepareStart()
            case .timedOut:
                step = .needInputMethod("等了很久还没看到鼠须管被添加。添加好后再点一次「打开系统设置」")
            case .reregistered:
                step = .needRestart
            case .notRegistered:
                step = .failed("系统里没有鼠须管的输入源，重新注册也没用。请重新安装鼠须管")
            }
        } catch {
            step = .failed("\(error)")
        }
    }

    // MARK: 第三步：看 Rime 目录

    func prepareStart() async {
        step = .working("正在看 Rime 目录里有没有已有的配置……")
        do {
            let rime = env.locations.rimeDirectory
            let catalog = env.catalog
            let survey = try await offMain { try TakeoverSurvey.scan(rime, catalog: catalog) }
            if survey.isEmpty {
                step = .chooseStart(.empty)
                return
            }
            guard !survey.schemas.isEmpty else {
                step = .chooseStart(.unrecognized)
                return
            }
            var packages = try await fetch(try env.catalog.installOrder(for: survey.packages))
            var textReplacement: [Phrase] = []
            var blocked: String?
            do {
                textReplacement = try env.textReplacements().usable
            } catch {
                // 读不到就分不出哪些短语来自文本替换：不能接管（和 rimectl takeover 一样）
                blocked = "读不了 macOS 文本替换（\(error)），分不出哪些短语来自文本替换，暂时不能接管"
            }
            step = .working("正在识别已有的配置……")
            let found = packages
            let replacements = textReplacement
            let proposal = try await offMain {
                try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: found, textReplacement: replacements)
            }
            let missing = try proposal.settings.requiredPackages(env.catalog).filter { packages[$0.id] == nil }
            packages.merge(try await fetch(missing)) { old, _ in old }
            step = .working("正在比对接管后会变的文件……")
            let all = packages
            let staging = env.paths.staging
            let preview = try await offMain {
                try TakeoverPreview.make(proposal, rime: rime, catalog: catalog, packages: all,
                                         textReplacement: replacements, staging: staging)
            }
            pendingTakeover = blocked == nil ? (proposal, packages, textReplacement) : nil
            step = .chooseStart(.existing(TakeoverSummary.make(proposal, preview: preview, catalog: env.catalog,
                                                               blockedReason: blocked)))
        } catch {
            step = .failed("\(error)")
        }
    }

    /// 取这些包，界面上显示进度
    func fetch(_ specs: [PackageSpec]) async throws -> [String: CachedPackage] {
        var result: [String: CachedPackage] = [:]
        for (index, spec) in specs.enumerated() {
            step = .working("正在下载方案：\(spec.name)（\(index + 1)/\(specs.count)）……")
            result[spec.id] = try await env.fetchPackage(spec)
        }
        return result
    }

    // MARK: 起步方案

    public func useSettings(_ settings: Settings) async {
        do {
            let packages = try await fetch(try settings.requiredPackages(env.catalog))
            step = .working("正在生成配置、写入、部署……")
            let input = GenerationInput(settings: settings, catalog: env.catalog, packages: packages,
                                        personal: .empty, textReplacementPhrases: [])
            let paths = env.paths
            // Rime 目录里认不出的同名文件也覆盖：先完整备份，第一次的这份永久保留
            let deployer = env.deployer()
            let outcome = try await offMain {
                try await deployer.apply(input, options: ApplyOptions(overwriteExternalChanges: true),
                                         afterWrite: { try AppDataWriter.replace(settings: settings, dicts: [], phrases: [], paths: paths) })
            }
            finish(outcome, notes: [])
        } catch {
            step = .failed("\(error)")
        }
    }

    // MARK: 接管

    public func confirmTakeover() async {
        guard let pending = pendingTakeover else {
            await prepareStart()
            return
        }
        step = .working("正在接管：完整备份、写入、部署……")
        do {
            let applier = TakeoverApplier(deployer: env.deployer())
            let catalog = env.catalog
            let outcome = try await offMain {
                try await applier.confirm(pending.proposal, catalog: catalog, packages: pending.packages,
                                          textReplacement: pending.textReplacement, force: true)
            }
            pendingTakeover = nil
            finish(outcome, notes: [])
        } catch {
            step = .failed("\(error)")
        }
    }

    // MARK: 从导出文件导入

    public func importFile(_ file: URL) async {
        step = .working("正在读取导出文件……")
        let work = env.paths.staging.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let accessing = file.startAccessingSecurityScopedResource()
        defer { if accessing { file.stopAccessingSecurityScopedResource() } }
        do {
            let catalog = env.catalog
            let archive = try await offMain { try ImportArchive.open(file, catalog: catalog, into: work) }
            let settings = archive.manifest.settings
            let packages = try await fetch(try settings.requiredPackages(env.catalog))
            var notes = archive.warnings
            var textReplacement: [Phrase] = []
            if settings.textReplacement.sync {
                do {
                    textReplacement = try env.textReplacements().usable
                } catch {
                    notes.append("读不了 macOS 文本替换（\(error)），这次先不带文本替换的短语")
                }
            }
            step = .working(archive.userDB.isEmpty
                ? "正在写入、部署……"
                : "正在写入、部署，然后合并输入习惯（输入法会暂停几秒）……")
            let importer = Importer(deployer: env.deployer(),
                                    userDB: UserDBTransfer(tool: env.userDBTool, squirrel: env.squirrel, sleep: env.sleep))
            let replacements = textReplacement
            let report = try await offMain {
                try await importer.run(archive, catalog: catalog, packages: packages, textReplacement: replacements)
            }
            if let previous = report.previous { notes.append("应用里原来的设置和个人内容另存在：\(previous.path)") }
            if let error = report.userDBError { notes.append("输入习惯没有合并上：\(error)。配置已经导入好了，可以再导入一次") }
            finish(report.outcome, notes: notes)
        } catch {
            step = .failed("\(error)")
        }
    }

    /// 重活（读写文件、复制方案包、等部署）放到后台做，界面不卡
    func offMain<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Task.detached(operation: body).value
    }

    // MARK: 结果

    func finish(_ outcome: ApplyOutcome, notes: [String]) {
        switch outcome {
        case .applied(let report):
            var lines = ["鼠须管已经设置好了，可以打字了"]
            if !report.deploy.finished { lines.append("等了很久还没看到部署完成，可能还在部署；过一会儿再试试打字") }
            lines += report.deploy.errors.map { "部署时有错误：\($0)" }
            lines += report.warnings + notes
            step = .done(lines)
        case .compileFailed(let errors):
            step = .failed((["新配置编译不过，没有写入："] + errors).joined(separator: "\n"))
        case .externalChanges(let changes):
            step = .failed((["这些文件不能写，没有写入："] + changes.map(\.description)).joined(separator: "\n"))
        }
    }
}
