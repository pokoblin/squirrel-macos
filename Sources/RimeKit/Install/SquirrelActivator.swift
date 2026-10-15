import Foundation

public enum ActivationOutcome: Sendable, Equatable {
    /// 鼠须管可以用了。openedSettings：等过用户在系统设置里添加；launched：启动了鼠须管
    case ready(openedSettings: Bool, launched: Bool)
    /// 等到时间用户还没添加
    case timedOut
    /// 系统里没有鼠须管的输入源（安装没注册上），建议重新安装
    case notRegistered
}

/// 启用鼠须管（设计 6.2 第 1 步后半）：没添加就打开系统设置等用户添加 → 切换过去 → 没运行就启动
public struct SquirrelActivator: Sendable {
    let locations: RimeLocations
    let inputSource: any InputSourceControlling
    let squirrel: any SquirrelControlling
    let watcher: DeployWatcher
    let timeout: Double
    let pollInterval: Double

    public init(locations: RimeLocations, inputSource: any InputSourceControlling, squirrel: any SquirrelControlling,
                watcher: DeployWatcher, timeout: Double = 600, pollInterval: Double = 1) {
        self.locations = locations
        self.inputSource = inputSource
        self.squirrel = squirrel
        self.watcher = watcher
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    /// onWaiting：打开系统设置、开始等用户添加时调用一次（界面或命令行在这里告诉用户怎么做）
    public func activate(onWaiting: @Sendable () -> Void = {}) async throws -> ActivationOutcome {
        guard locations.squirrelInstalled else { throw ApplyError.squirrelNotInstalled }
        var state = inputSource.state()
        guard state.registered else { return .notRegistered }

        var opened = false
        if !state.enabled {
            try inputSource.openKeyboardSettings()
            opened = true
            onWaiting()
            var waited = 0.0
            while !state.enabled {
                if waited >= timeout { return .timedOut }
                await inputSource.pump(pollInterval)
                waited += pollInterval
                state = inputSource.state()
            }
        }
        if !state.selected { try inputSource.selectSquirrel() }

        var launched = false
        if !squirrel.isRunning() {
            let previous = watcher.lastBuildTime()
            let snapshot = watcher.snapshot()
            try squirrel.launch()
            launched = true
            _ = await watcher.wait(previousBuildTime: previous, since: snapshot)   // 等它第一次部署完，~/Library/Rime 就有了
        }
        return .ready(openedSettings: opened, launched: launched)
    }
}
