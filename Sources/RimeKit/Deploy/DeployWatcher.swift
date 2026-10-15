import Foundation

public struct DeployOutcome: Sendable, Equatable {
    /// 在超时前看到了部署完成
    public let finished: Bool
    /// 这次部署新出现的错误（已翻译成白话）
    public let errors: [String]
    /// 通知到了鼠须管（重新加载或启动）。没通知到时根本没等，鼠须管也不会自己部署
    public let notified: Bool

    public init(finished: Bool, errors: [String], notified: Bool = true) {
        self.finished = finished
        self.errors = errors
        self.notified = notified
    }

    /// 没看到部署完成时，界面上怎么说
    public var notFinishedNote: String {
        notified
            ? "等了很久还没看到部署完成，可能还在部署；过一会儿再试试打字"
            : "没通知到鼠须管，配置已经写好但还没部署：切换一下输入法，或者从「应用程序」里打开鼠须管，它会自己部署"
    }
}

/// 日志目录里各个 ERROR 文件当时的大小
public struct LogSnapshot: Sendable, Equatable {
    let sizes: [String: Int]
}

/// 等鼠须管部署完：user.yaml 的 var/last_build_time 每次部署都会更新（实测，配置没变也会），
/// 所以看它变没变；不看 build/ 里文件的修改时间（只改外观时方案不会重编译）。
public struct DeployWatcher: Sendable {
    let locations: RimeLocations
    let pollInterval: Duration
    let timeout: Duration
    let sleep: @Sendable (Duration) async -> Void

    public init(
        locations: RimeLocations,
        pollInterval: Duration = .seconds(1),
        timeout: Duration = .seconds(120),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.locations = locations
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.sleep = sleep
    }

    public func lastBuildTime() -> Int? {
        let url = locations.rimeDirectory.appending(path: "user.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let root = try? YAMLNode.parse(text) else { return nil }
        return root["var"]?["last_build_time"]?.int
    }

    public func snapshot() -> LogSnapshot {
        LogSnapshot(sizes: Dictionary(uniqueKeysWithValues: errorFiles().map { ($0, size(of: $0)) }))
    }

    /// 从快照之后新写进 ERROR 日志的错误行
    public func newErrorLines(since snapshot: LogSnapshot) -> [String] {
        var lines: [String] = []
        for name in errorFiles() {
            let url = locations.logDirectory.appending(path: name)
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: UInt64(snapshot.sizes[name] ?? 0))
            let data = (try? handle.readToEnd()) ?? Data()
            lines += RimeLog.errorLines(String(decoding: data, as: UTF8.self))
        }
        return lines
    }

    public func wait(previousBuildTime: Int?, since snapshot: LogSnapshot) async -> DeployOutcome {
        var waited = Duration.zero
        while waited < timeout {
            if let time = lastBuildTime(), time != previousBuildTime {
                await sleep(pollInterval)   // 让错误日志写完（glog 有缓冲）
                return DeployOutcome(finished: true, errors: RimeLog.explain(newErrorLines(since: snapshot)))
            }
            await sleep(pollInterval)
            waited += pollInterval
        }
        return DeployOutcome(finished: false, errors: RimeLog.explain(newErrorLines(since: snapshot)))
    }

    /// 日志目录里的 ERROR 文件名（rime.squirrel.<主机>.<用户>.log.ERROR.<时间>.<进程号>）
    private func errorFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: locations.logDirectory.path)) ?? []
        return names.filter { $0.contains(".log.ERROR.") }.sorted()
    }

    private func size(of name: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: locations.logDirectory.appending(path: name).path)
        return (attributes?[.size] as? Int) ?? 0
    }
}
