import Foundation

public enum ActivationOutcome: Sendable, Equatable {
    /// 鼠须管可以用了。openedSettings：等过用户在系统设置里添加；launched：启动了鼠须管
    case ready(openedSettings: Bool, launched: Bool)
    /// 等到时间用户还没添加
    case timedOut
    /// 系统里没有鼠须管的输入源，重新注册了也还是没有
    case notRegistered
}

/// 启用鼠须管（设计 6.2 第 1 步后半）：输入源丢了就重新注册 → 没添加就打开系统设置等用户添加 → 切换过去 → 没运行就启动
public struct SquirrelActivator: Sendable {
    let locations: RimeLocations
    let inputSource: any InputSourceControlling
    let squirrel: any SquirrelControlling
    let watcher: DeployWatcher
    let timeout: Double
    let pollInterval: Double
    /// 重新注册后最多等多久让输入源出现
    let registrationTimeout: Double

    public init(locations: RimeLocations, inputSource: any InputSourceControlling, squirrel: any SquirrelControlling,
                watcher: DeployWatcher, timeout: Double = 600, pollInterval: Double = 1, registrationTimeout: Double = 5) {
        self.locations = locations
        self.inputSource = inputSource
        self.squirrel = squirrel
        self.watcher = watcher
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.registrationTimeout = registrationTimeout
    }

    /// onRegistering：输入源不在系统里、开始重新注册时调用一次
    /// onWaiting：打开系统设置、开始等用户添加时调用一次（界面或命令行在这里告诉用户怎么做）
    public func activate(onRegistering: @Sendable () -> Void = {}, onWaiting: @Sendable () -> Void = {}) async throws -> ActivationOutcome {
        guard locations.squirrelInstalled else { throw ApplyError.squirrelNotInstalled }
        var state = inputSource.state()
        if !state.registered {
            onRegistering()
            try squirrel.registerInputSource()
            var waited = 0.0
            while !state.registered {
                if waited >= registrationTimeout { return .notRegistered }
                await inputSource.pump(pollInterval)   // TIS 有缓存，要让系统通知进来才看得到新注册的
                waited += pollInterval
                state = inputSource.state()
            }
        }

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
