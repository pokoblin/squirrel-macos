import Foundation
import Observation
import RimeKit

/// 整个应用的状态：先走第一次打开的引导，设置好了进主窗口
@MainActor @Observable
public final class AppState {
    public let setup: SetupFlow
    public private(set) var main: MainModel?
    /// 打不开主窗口时的原因
    public private(set) var openError: String?
    let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
        setup = SetupFlow(env: env)
    }

    /// 打开应用时建 AppState；建不了时（例如方案清单坏了）返回原因，界面上显示
    public static func launch(_ make: () throws -> AppEnvironment) -> (state: AppState?, error: String?) {
        do {
            return (AppState(env: try make()), nil)
        } catch {
            return (nil, "\(error)")
        }
    }

    /// 打开应用时：已经由应用管理的直接进主窗口
    public func start() async {
        guard main == nil else { return }
        await setup.start()
        if case .done = setup.step {
            openMain(welcome: [])
            await main?.checkTextReplacementAtLaunch()
        }
    }

    /// 引导完成页点「开始使用」
    public func openMain(welcome: [String]) {
        do {
            main = try MainModel(env: env, welcome: welcome)
            openError = nil
        } catch {
            openError = "\(error)"
        }
    }
}
