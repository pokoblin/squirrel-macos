import Foundation

public struct CompileReport: Sendable, Equatable {
    public let succeeded: Bool
    /// 原始的 E 开头的日志行
    public let errors: [String]

    public init(succeeded: Bool, errors: [String]) {
        self.succeeded = succeeded
        self.errors = errors
    }
}

/// 在一个目录上编译 Rime 配置，判断能不能用
public protocol RimeCompiler: Sendable {
    func compile(_ directory: URL) throws -> CompileReport
}

/// 用鼠须管自带的 rime_deployer 编译。补丁 YAML 写坏时退出码仍是 0，只有 E 行，所以两样都要看。
public struct DeployerCompiler: RimeCompiler {
    let locations: RimeLocations

    public init(locations: RimeLocations) {
        self.locations = locations
    }

    public func compile(_ directory: URL) throws -> CompileReport {
        let r = try Shell.run(locations.deployerBinary.path, [
            "--build", directory.path, locations.sharedSupport.path,
            directory.appending(path: "build", directoryHint: .isDirectory).path,
        ])
        let errors = RimeLog.errorLines(r.stdout + "\n" + r.stderr)
        return CompileReport(succeeded: r.status == 0 && errors.isEmpty, errors: errors)
    }
}

/// Rime（glog）日志的处理
public enum RimeLog {
    /// E 开头的错误行：E20261015 14:07:26.214222 0x… file.cc:86] 内容
    public static func errorLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            line.first == "E" && line.dropFirst().prefix(8).count == 8 && line.dropFirst().prefix(8).allSatisfy(\.isNumber)
        }
    }

    /// 把错误行翻译成白话，去重，保持顺序
    public static func explain(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let message = line.range(of: "] ").map { String(line[$0.upperBound...]) } ?? line
            let text = translate(message)
            if !result.contains(text) { result.append(text) }
        }
        return result
    }

    static func translate(_ message: String) -> String {
        if let m = message.firstMatch(of: /neither (.+)\.dict\.yaml nor/) {
            return "找不到词库 \(m.1)（缺少 \(m.1).dict.yaml）"
        }
        if let m = message.firstMatch(of: /dictionary '([^']+)' failed to compile/) {
            return "词库 \(m.1) 编译失败"
        }
        if let m = message.firstMatch(of: /Error parsing YAML "([^"]+)"/) {
            return "\((String(m.1) as NSString).lastPathComponent) 的格式不对（不是合法的 YAML）"
        }
        if let m = message.firstMatch(of: /invalid schema definition in '([^']+)'/) {
            return "方案文件 \((String(m.1) as NSString).lastPathComponent) 的内容不对"
        }
        return "Rime 报错：\(message)"
    }
}
