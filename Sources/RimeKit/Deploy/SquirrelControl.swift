import Darwin
import Foundation

/// 控制鼠须管：看在不在运行、通知重新部署、启动、重新注册输入源
public protocol SquirrelControlling: Sendable {
    func isRunning() -> Bool
    func reload() throws
    func launch() throws
    func registerInputSource() throws
}

public enum SquirrelError: Error, Equatable, Sendable, CustomStringConvertible {
    case commandFailed(String, String)

    public var description: String {
        switch self {
        case let .commandFailed(command, message): return "\(command) 失败：\(message)"
        }
    }
}

/// 真正的鼠须管。--reload 只对正在运行的鼠须管有效；没运行时要 open 启动它（实测）。
/// 需要在用户的桌面会话里运行（测试机里用 launchctl asuser）。
public struct SquirrelControl: SquirrelControlling {
    let locations: RimeLocations

    public init(locations: RimeLocations) {
        self.locations = locations
    }

    public func isRunning() -> Bool {
        (try? Shell.run("/usr/bin/pgrep", ["-x", "-U", String(getuid()), "Squirrel"]))?.status == 0
    }

    public func reload() throws {
        let r = try Shell.run(locations.squirrelBinary.path, ["--reload"])
        guard r.status == 0 else { throw SquirrelError.commandFailed("Squirrel --reload", r.stderr) }
    }

    public func launch() throws {
        let r = try Shell.run("/usr/bin/open", [locations.squirrelApp.path])
        guard r.status == 0 else { throw SquirrelError.commandFailed("open 鼠须管", r.stderr) }
    }

    /// 输入源从系统里消失时用（阶段 5 测试机实测：运行这条命令马上就回来了）。
    /// 重装不一定有用：postinstall 认为「已经注册过」就跳过注册
    public func registerInputSource() throws {
        let r = try Shell.run(locations.squirrelBinary.path, ["--register-input-source"])
        guard r.status == 0 else { throw SquirrelError.commandFailed("Squirrel --register-input-source", r.stderr) }
    }
}
