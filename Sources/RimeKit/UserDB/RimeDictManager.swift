import Foundation

public enum UserDBError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 数据库正被鼠须管占着
    case locked(String)
    case failed(String, String)
    /// 退出后又被系统马上拉起来，重试几次还是占着
    case stillLocked(String)
    case badName(String)

    public var description: String {
        switch self {
        case .locked(let name):
            return "输入习惯 \(name) 正被鼠须管使用"
        case let .failed(name, message):
            return "处理输入习惯 \(name) 失败：\(message)"
        case .stillLocked(let name):
            return "鼠须管一直占着输入习惯 \(name)（退出后又被系统马上启动了）。请先别打字，再试一次"
        case .badName(let name):
            return "输入习惯的名字不对：\(name)"
        }
    }
}

/// 导出、合并输入习惯的工具（测试时换成假的）
public protocol UserDBTool: Sendable {
    /// Rime 目录里有哪些输入习惯（词典名）
    func list() throws -> [String]
    func export(_ name: String, to file: URL) throws
    /// 合并（不是覆盖）：已有的条目不丢、不重复计数（已实测）
    func importSnapshot(_ name: String, from file: URL) throws
}

/// 鼠须管自带的 rime_dict_manager。它把当前目录当 Rime 用户目录（已实测），所以每次都在 Rime 目录里运行
public struct RimeDictManager: UserDBTool {
    let tool: URL
    let rimeDirectory: URL

    public init(locations: RimeLocations) {
        self.init(tool: locations.squirrelApp.appending(path: "Contents/MacOS/rime_dict_manager"),
                  rimeDirectory: locations.rimeDirectory)
    }

    public init(tool: URL, rimeDirectory: URL) {
        self.tool = tool
        self.rimeDirectory = rimeDirectory
    }

    /// 词典名只能是字母、数字、_ - .，不能以 . 开头（会拼进文件名和命令参数）
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") }
    }

    public func list() throws -> [String] {
        let r = try run(["--list"])
        guard r.status == 0 else { throw UserDBError.failed("--list", r.stderr) }
        // 没有时输出 "No user dictionary is found."（有空格，不是合法名字，自然被滤掉）
        return r.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(Self.isValidName)
    }

    public func export(_ name: String, to file: URL) throws {
        guard Self.isValidName(name) else { throw UserDBError.badName(name) }
        try check(name, try run(["--export", name, file.path]))
    }

    public func importSnapshot(_ name: String, from file: URL) throws {
        guard Self.isValidName(name) else { throw UserDBError.badName(name) }
        try check(name, try run(["--import", name, file.path]))
    }

    func check(_ name: String, _ r: ShellResult) throws {
        guard r.status == 0 else {
            let message = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            // 鼠须管占着时：Error opening db 'rime_ice' read-only.（已实测）
            if message.contains("Error opening db") { throw UserDBError.locked(name) }
            throw UserDBError.failed(name, message)
        }
    }

    func run(_ arguments: [String]) throws -> ShellResult {
        try FileManager.default.createDirectory(at: rimeDirectory, withIntermediateDirectories: true)
        return try Shell.run(tool.path, arguments, currentDirectory: rimeDirectory)
    }
}
