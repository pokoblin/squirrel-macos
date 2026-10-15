import Foundation

public enum CheckLevel: String, Sendable {
    case ok, warning, problem
}

public struct DoctorCheck: Sendable, Equatable {
    public let name: String
    public let level: CheckLevel
    public let message: String
    /// 下一步该做什么
    public let hint: String?

    public init(name: String, level: CheckLevel, message: String, hint: String? = nil) {
        self.name = name
        self.level = level
        self.message = message
        self.hint = hint
    }
}

/// 环境检查：逐项看，告诉用户下一步做什么（设计 6.2 第 1 步）
public struct Doctor: Sendable {
    let paths: AppPaths
    let locations: RimeLocations
    let inputSource: any InputSourceControlling
    let squirrel: any SquirrelControlling
    /// 为空表示不联网查最新版本
    let releaseSource: SquirrelReleaseSource?

    public init(paths: AppPaths, locations: RimeLocations, inputSource: any InputSourceControlling,
                squirrel: any SquirrelControlling, releaseSource: SquirrelReleaseSource?) {
        self.paths = paths
        self.locations = locations
        self.inputSource = inputSource
        self.squirrel = squirrel
        self.releaseSource = releaseSource
    }

    public func run() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        guard let version = locations.installedSquirrelVersion, locations.squirrelInstalled else {
            checks.append(DoctorCheck(name: "鼠须管", level: .problem, message: "还没有安装", hint: "运行 rimectl install"))
            checks.append(settingsCheck())
            return checks
        }
        checks.append(await squirrelCheck(version))
        checks.append(inputCheck())
        checks.append(squirrel.isRunning()
            ? DoctorCheck(name: "鼠须管进程", level: .ok, message: "正在运行")
            : DoctorCheck(name: "鼠须管进程", level: .warning, message: "没在运行", hint: "运行 rimectl activate"))
        checks.append(rimeDirectoryCheck())
        checks.append(settingsCheck())
        checks.append(managedCheck())
        return checks
    }

    private func squirrelCheck(_ version: String) async -> DoctorCheck {
        guard let releaseSource else {
            return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)")
        }
        do {
            let latest = try await releaseSource.latest().version
            if let have = SquirrelVersion(version), let newest = SquirrelVersion(latest), have < newest {
                return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)（最新是 \(latest)，鼠须管会自己提示更新）")
            }
            return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)（是最新版）")
        } catch {
            return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)（查不到最新版本：\(error)）")
        }
    }

    private func inputCheck() -> DoctorCheck {
        let s = inputSource.state()
        if !s.registered {
            return DoctorCheck(name: "输入法", level: .problem, message: "系统里没有鼠须管的输入源", hint: "运行 rimectl install --force 重新安装")
        }
        if !s.enabled {
            return DoctorCheck(name: "输入法", level: .problem, message: "还没有在系统设置里添加鼠须管", hint: "运行 rimectl activate")
        }
        if !s.selected {
            return DoctorCheck(name: "输入法", level: .warning, message: "已添加，但现在选中的不是鼠须管", hint: "运行 rimectl activate，或按输入法切换键")
        }
        return DoctorCheck(name: "输入法", level: .ok, message: "已添加并选中鼠须管")
    }

    private func rimeDirectoryCheck() -> DoctorCheck {
        let watcher = DeployWatcher(locations: locations)
        guard let time = watcher.lastBuildTime() else {
            return DoctorCheck(name: "Rime 目录", level: .warning, message: "鼠须管还没部署过", hint: "运行 rimectl activate")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(time)).formatted(date: .numeric, time: .shortened)
        return DoctorCheck(name: "Rime 目录", level: .ok, message: "上次部署：\(date)")
    }

    private func settingsCheck() -> DoctorCheck {
        let exists = (try? SettingsStore(paths: paths).load()) != nil
        return exists
            ? DoctorCheck(name: "设置", level: .ok, message: "已有设置")
            : DoctorCheck(name: "设置", level: .warning, message: "还没有设置", hint: "运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
    }

    private func managedCheck() -> DoctorCheck {
        guard let ledger = try? Ledger.load(paths), ledger.appliedAt != nil else {
            return DoctorCheck(name: "应用管理的配置", level: .warning, message: "还没应用过设置", hint: "运行 rimectl apply")
        }
        let changes = ledger.externalChanges(in: locations.rimeDirectory)
        if changes.isEmpty {
            return DoctorCheck(name: "应用管理的配置", level: .ok, message: "\(ledger.entries.count) 个文件，没有外部改动")
        }
        return DoctorCheck(name: "应用管理的配置", level: .warning, message: "有 \(changes.count) 个文件在应用外被改过或删了",
                           hint: "运行 rimectl status 看是哪些；rimectl apply 会先问你")
    }
}
