import Darwin
import Foundation

public struct ApplyOptions: Sendable, Equatable {
    /// 外部改动、应用不管的文件也照样覆盖（先备份）
    public var overwriteExternalChanges: Bool
    /// 在应用外改过的个人词库，收回到 personal/ 当正本
    public var adoptPersonalChanges: Bool

    public init(overwriteExternalChanges: Bool = false, adoptPersonalChanges: Bool = false) {
        self.overwriteExternalChanges = overwriteExternalChanges
        self.adoptPersonalChanges = adoptPersonalChanges
    }
}

public struct ApplyReport: Sendable, Equatable {
    public let backup: BackupInfo
    public let written: [String]
    public let unchanged: Int
    public let removed: [String]
    /// 鼠须管原来没运行，这次启动了它
    public let launched: Bool
    public let deploy: DeployOutcome
    public let warnings: [String]
}

public enum ApplyOutcome: Sendable, Equatable {
    case applied(ApplyReport)
    /// 有外部改动，没让覆盖，什么都没写
    case externalChanges([ExternalChange])
    /// 暂存区编译失败（已翻译），什么都没写
    case compileFailed([String])
}

public struct RestoreReport: Sendable, Equatable {
    public let restored: BackupInfo
    /// 还原前给当时的状态做的备份，还原也能撤销
    public let safetyBackup: BackupInfo
    public let launched: Bool
    public let deploy: DeployOutcome
    public let warnings: [String]
}

public struct DeployStatus: Sendable, Equatable {
    public let squirrelInstalled: Bool
    public let squirrelRunning: Bool
    public let rimeDirectory: URL
    public let managedFiles: Int
    public let appliedAt: Date?
    public let externalChanges: [ExternalChange]
    public let backups: [BackupInfo]
}

/// 把设置应用到真实的 ~/Library/Rime（设计 6.1）
public struct Deployer: Sendable {
    public let paths: AppPaths
    public let locations: RimeLocations
    let compiler: any RimeCompiler
    let squirrel: any SquirrelControlling
    let watcher: DeployWatcher
    let now: @Sendable () -> Date

    public init(
        paths: AppPaths,
        locations: RimeLocations,
        compiler: any RimeCompiler,
        squirrel: any SquirrelControlling,
        watcher: DeployWatcher,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.locations = locations
        self.compiler = compiler
        self.squirrel = squirrel
        self.watcher = watcher
        self.now = now
    }

    public func apply(_ input: GenerationInput, options: ApplyOptions = ApplyOptions()) async throws -> ApplyOutcome {
        guard locations.squirrelInstalled else { throw ApplyError.squirrelNotInstalled }
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let fm = FileManager.default
        let rime = locations.rimeDirectory
        let ledger = try Ledger.load(paths)
        var input = input

        let work = paths.staging.appending(path: "apply-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }

        // 1. 已管理的文件有没有在应用外被改过；需要的话采用个人词库的外部修改
        //    （先放在暂存区，写入成功后才放回 personal/，中途停下不会动正本）
        var changes = ledger.externalChanges(in: rime)
        var adopted: [(path: String, staged: URL)] = []
        if options.adoptPersonalChanges {
            adopted = try stageAdoptedPersonal(changes, ledger: ledger, into: work.appending(path: "adopted", directoryHint: .isDirectory))
            let names = Set(adopted.map { $0.staged.lastPathComponent })
            if !names.isEmpty {
                input.personal.dicts = (input.personal.dicts.filter { !names.contains($0.lastPathComponent) } + adopted.map(\.staged))
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                let adoptedPaths = Set(adopted.map(\.path))
                changes.removeAll { adoptedPaths.contains($0.path) }
            }
        }

        // 2. 在暂存区生成
        let generated = work.appending(path: "generated", directoryHint: .isDirectory)
        let result = try ConfigGenerator().generate(input, into: generated)
        let newPaths = result.files.map(\.path)
        // 要写、要删的文件所在的目录如果经符号链接指到 Rime 目录外面，一律不写（--overwrite 也不行）
        let outside = (newPaths + ledger.entries.keys.sorted()).filter { !Self.isInside(rime, $0) }
        if !outside.isEmpty {
            return .externalChanges(Array(Set(outside)).sorted().map { .outsideRimeDirectory($0) })
        }
        changes += ledger.unmanagedOverwrites(newPaths, in: rime)
        if !changes.isEmpty, !options.overwriteExternalChanges {
            return .externalChanges(changes)
        }

        // 3. 拼出完整的目录编译：现有的、应用不管也不会覆盖的配置文件 + 新生成的
        let full = work.appending(path: "full", directoryHint: .isDirectory)
        let existing = try RimeFiles.configFiles(in: rime)
        let newSet = Set(newPaths)
        for path in existing where ledger.entries[path] == nil && !newSet.contains(path) {
            try Self.copy(rime.appending(path: path), to: full.appending(path: path))
        }
        for path in newPaths {
            try Self.copy(generated.appending(path: path), to: full.appending(path: path))
        }
        let compiled = try compiler.compile(full)
        guard compiled.succeeded else { return .compileFailed(RimeLog.explain(compiled.errors)) }

        // 4. 备份
        let backups = BackupStore(paths: paths, now: now)
        let first = ledger.entries.isEmpty
        // 永久保留只要一份：还原到第一次应用前再应用时，不再加新的永久备份
        let keep = first && !existing.isEmpty && !backups.list().contains(where: \.permanent)
        let backup = try backups.create(from: rime, reason: first ? "第一次应用前" : "应用改动前",
                                        permanent: keep, ledger: ledger)

        // 5. 写入；出错就用刚才的备份还原
        var written: [String] = []
        var unchanged = 0
        var removed: [String] = []
        do {
            try fm.createDirectory(at: rime, withIntermediateDirectories: true)
            var newLedger = Ledger(appliedAt: now())
            for file in result.files {
                let source = generated.appending(path: file.path)
                let sha = try Hashing.sha256(of: source)
                newLedger.entries[file.path] = LedgerEntry(sha256: sha, origin: file.origin.ledgerValue)
                let target = rime.appending(path: file.path)
                if ledger.entries[file.path]?.sha256 == sha, (try? Hashing.sha256(of: target)) == sha {
                    unchanged += 1
                    continue
                }
                try Self.replace(target, with: source)
                written.append(file.path)
            }
            for path in ledger.entries.keys.sorted() where newLedger.entries[path] == nil {
                let url = rime.appending(path: path)
                if Ledger.exists(url) {
                    try fm.removeItem(at: url)
                    removed.append(path)
                }
            }
            try newLedger.save(paths)
            for item in adopted {
                try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
                try Self.replace(paths.personalDicts.appending(path: item.staged.lastPathComponent), with: item.staged)
            }
        } catch {
            let restored = (try? backups.restore(backup.id, to: rime, managed: Set(written))) != nil
            if restored { try? ledger.save(paths) }
            throw ApplyError.writeFailed(String(describing: error), restored: restored, backupID: backup.id)
        }
        _ = try? backups.prune()

        // 6. 通知鼠须管，等部署完
        let (launched, deploy, notifyWarnings) = await notifySquirrel()
        return .applied(ApplyReport(backup: backup, written: written, unchanged: unchanged, removed: removed,
                                    launched: launched, deploy: deploy, warnings: result.warnings + notifyWarnings))
    }

    /// 还原到某个备份：先备份当前状态（「还原前」），再还原文件和 ledger，然后通知鼠须管
    public func restore(_ id: String) async throws -> RestoreReport {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let backups = BackupStore(paths: paths, now: now)
        guard let target = backups.info(id) else { throw BackupError.notFound(id) }
        let safety = try backups.create(from: locations.rimeDirectory, reason: "还原前", permanent: false,
                                        ledger: try Ledger.load(paths))
        let current = try Ledger.load(paths)
        let restored: BackupInfo
        do {
            restored = try backups.restore(target.id, to: locations.rimeDirectory, managed: Set(current.entries.keys))
        } catch let error as BackupError {
            throw error   // 找不到、不完整：还没动任何文件
        } catch {
            // 放到一半失败：用还原前的备份回去
            let managed = Set(target.files).union(current.entries.keys)
            let rolledBack = (try? backups.restore(safety.id, to: locations.rimeDirectory, managed: managed)) != nil
            if rolledBack { try? current.save(paths) }
            throw RestoreError.failed(String(describing: error), safetyBackupID: safety.id, rolledBack: rolledBack)
        }
        try restored.ledger.save(paths)
        _ = try? backups.prune()
        let (launched, deploy, warnings) = await notifySquirrel()
        return RestoreReport(restored: restored, safetyBackup: safety, launched: launched, deploy: deploy, warnings: warnings)
    }

    public func status() throws -> DeployStatus {
        let ledger = try Ledger.load(paths)
        return DeployStatus(
            squirrelInstalled: locations.squirrelInstalled,
            squirrelRunning: squirrel.isRunning(),
            rimeDirectory: locations.rimeDirectory,
            managedFiles: ledger.entries.count,
            appliedAt: ledger.appliedAt,
            externalChanges: ledger.externalChanges(in: locations.rimeDirectory),
            backups: BackupStore(paths: paths).list())
    }

    // MARK: 内部

    /// 在运行就 --reload，没运行就启动；然后等部署完
    func notifySquirrel() async -> (launched: Bool, deploy: DeployOutcome, warnings: [String]) {
        let previous = watcher.lastBuildTime()
        let snapshot = watcher.snapshot()
        var launched = false
        var warnings: [String] = []
        do {
            if squirrel.isRunning() {
                try squirrel.reload()
            } else {
                try squirrel.launch()
                launched = true
            }
        } catch {
            warnings.append("通知鼠须管失败：\(error)")
        }
        let deploy = await watcher.wait(previousBuildTime: previous, since: snapshot)
        return (launched, deploy, warnings)
    }

    /// 把在应用外改过的个人词库先复制到暂存区（写入成功后才放回 personal/）
    private func stageAdoptedPersonal(_ changes: [ExternalChange], ledger: Ledger, into dir: URL) throws -> [(path: String, staged: URL)] {
        var result: [(path: String, staged: URL)] = []
        for case .modified(let path) in changes where ledger.entries[path]?.origin == FileOrigin.personal.ledgerValue {
            let staged = dir.appending(path: (path as NSString).lastPathComponent)
            try Self.copy(locations.rimeDirectory.appending(path: path), to: staged)
            result.append((path, staged))
        }
        return result
    }

    /// 复制到暂存区：符号链接换成它指向的真实内容（相对链接直接复制过去会断）；指向不存在的链接跳过
    static func copy(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        let real = source.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: real.path) else { return }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: real, to: target)
    }

    /// 这个相对路径所在的目录（解析符号链接后）还在 Rime 目录里吗
    static func isInside(_ rime: URL, _ path: String) -> Bool {
        let root = rime.resolvingSymlinksInPath().path
        var parent = rime.appending(path: path).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
            parent = parent.deletingLastPathComponent()
        }
        // Rime 目录自己还不存在：下面的都是新建的，当然在里面
        if rime.standardizedFileURL.path.hasPrefix(parent.standardizedFileURL.path + "/") { return true }
        let resolved = parent.resolvingSymlinksInPath().path
        return resolved == root || resolved.hasPrefix(root + "/")
    }

    /// 先复制成同目录下的临时文件，再 rename 过去：不会出现写了一半的文件
    static func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temp = parent.appending(path: ".\(target.lastPathComponent).squirrel-macos-tmp")
        try? fm.removeItem(at: temp)
        try fm.copyItem(at: source, to: temp)
        guard rename(temp.path, target.path) == 0 else {
            let code = errno
            try? fm.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
