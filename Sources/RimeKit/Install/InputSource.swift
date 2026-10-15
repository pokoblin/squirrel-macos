import Carbon
import Foundation

public struct InputSourceState: Sendable, Equatable {
    /// 系统里有鼠须管的主输入源（安装时注册的）
    public var registered: Bool
    /// 用户在系统设置里添加了鼠须管（主输入源 enabled）
    public var enabled: Bool
    /// 当前选中的是鼠须管
    public var selected: Bool

    public init(registered: Bool, enabled: Bool, selected: Bool) {
        self.registered = registered
        self.enabled = enabled
        self.selected = selected
    }
}

public enum InputSourceError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound
    case selectFailed(Int)
    case openSettingsFailed(String)

    public var description: String {
        switch self {
        case .notFound: return "系统里找不到「鼠须管 - 简体」输入源"
        case .selectFailed(let code): return "切换到鼠须管失败（OSStatus \(code)），可以按输入法切换键手动切换"
        case .openSettingsFailed(let message): return "打开系统设置失败：\(message)"
        }
    }
}

/// 查看、切换输入法；等待用户操作时让系统通知进来
public protocol InputSourceControlling: Sendable {
    func state() -> InputSourceState
    func selectSquirrel() throws
    func openKeyboardSettings() throws
    func pump(_ seconds: Double) async
}

/// 用 Carbon 的 TIS 接口（要在用户的桌面会话里运行）
public struct TISInputSourceService: InputSourceControlling {
    public static let mainID = "im.rime.inputmethod.Squirrel"
    public static let hansID = "im.rime.inputmethod.Squirrel.Hans"
    public static let settingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    public init() {}

    public func state() -> InputSourceState {
        let main = Self.sources().first { Self.id($0) == Self.mainID }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return InputSourceState(
            registered: main != nil,
            enabled: main.map { Self.bool($0, kTISPropertyInputSourceIsEnabled) } ?? false,
            selected: Self.id(current).hasPrefix(Self.mainID))
    }

    public func selectSquirrel() throws {
        guard let hans = Self.sources().first(where: { Self.id($0) == Self.hansID }) else { throw InputSourceError.notFound }
        let status = TISSelectInputSource(hans)
        guard status == noErr else { throw InputSourceError.selectFailed(Int(status)) }
    }

    public func openKeyboardSettings() throws {
        let r = try Shell.run("/usr/bin/open", [Self.settingsURL])
        guard r.status == 0 else { throw InputSourceError.openSettingsFailed(r.stderr) }
    }

    /// 等待时让主线程的 run loop 转起来，系统发来的「输入源变了」通知才能更新 TIS 的缓存（任务 1 实测）
    public func pump(_ seconds: Double) async {
        await MainActor.run { _ = CFRunLoopRunInMode(.defaultMode, seconds, false) }
    }

    static func sources() -> [TISInputSource] {
        (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    static func id(_ source: TISInputSource) -> String {
        property(source, kTISPropertyInputSourceID) ?? ""
    }

    static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        (property(source, key) as Bool?) ?? false
    }

    static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let p = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
    }
}
