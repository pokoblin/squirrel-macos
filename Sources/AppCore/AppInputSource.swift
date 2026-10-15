import Foundation
import RimeKit

/// 应用里用的输入法服务：TIS 的调用照旧（在主线程上做），等待时只 sleep，不再嵌套转 run loop。
/// 应用的主 run loop 本来就在转，系统的「输入源变了」通知会自己进来（阶段 4 的待改进项）
public struct AppInputSource: InputSourceControlling {
    let base = TISInputSourceService()

    public init() {}

    public func state() -> InputSourceState { base.state() }
    public func selectSquirrel() throws { try base.selectSquirrel() }
    public func openKeyboardSettings() throws { try base.openKeyboardSettings() }
    public func pump(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
}
