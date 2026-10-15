import Foundation

/// 导出、合并输入习惯的结果
public struct UserDBResult: Sendable, Equatable {
    public let names: [String]
    /// 导出、合并都做完了，只是最后重新启动鼠须管失败：提醒用户自己切换一下输入法
    public let warning: String?

    public init(names: [String], warning: String? = nil) {
        self.names = names
        self.warning = warning
    }
}

/// 导出、合并输入习惯（设计 6.3、6.4）：鼠须管占着数据库时导不出来（已实测），
/// 所以先退出它；退出后用户一打字系统可能马上又把它拉起来，所以被占着就再退出一次重试
public struct UserDBTransfer: Sendable {
    let tool: any UserDBTool
    let squirrel: any SquirrelControlling
    let attempts: Int
    let sleep: @Sendable (Duration) async -> Void

    public init(tool: any UserDBTool, squirrel: any SquirrelControlling, attempts: Int = 3,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.tool = tool
        self.squirrel = squirrel
        self.attempts = attempts
        self.sleep = sleep
    }

    /// 导出全部输入习惯到 dir/<名字>.userdb.txt，返回名字（排序）。原来在运行的鼠须管做完重新启动
    public func exportAll(into dir: URL) async throws -> UserDBResult {
        let names = try tool.list().sorted()
        guard !names.isEmpty else { return UserDBResult(names: []) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wasRunning = squirrel.isRunning()
        do {
            for name in names {
                try await withSquirrelStopped(name) { try tool.export(name, to: dir.appending(path: "\(name).userdb.txt")) }
            }
        } catch {
            if wasRunning { try? squirrel.launch() }
            throw error
        }
        return UserDBResult(names: names, warning: wasRunning ? relaunch() : nil)
    }

    /// 把快照合并进输入习惯（名字 → 快照文件），做完启动鼠须管
    public func importAll(_ files: [String: URL]) async throws -> UserDBResult {
        let names = files.keys.sorted()
        guard !names.isEmpty else { return UserDBResult(names: []) }
        do {
            for name in names {
                try await withSquirrelStopped(name) { try tool.importSnapshot(name, from: files[name]!) }
            }
        } catch {
            try? squirrel.launch()
            throw error
        }
        return UserDBResult(names: names, warning: relaunch())
    }

    /// 做完后重新启动鼠须管。失败不算整件事失败，返回提醒
    func relaunch() -> String? {
        do {
            try squirrel.launch()
            return nil
        } catch {
            return "重新启动鼠须管失败（\(error)）：切换一下输入法，或者从「应用程序」里打开鼠须管"
        }
    }

    func withSquirrelStopped(_ name: String, _ body: () throws -> Void) async throws {
        for attempt in 1...attempts {
            try await stopSquirrel()
            do {
                try body()
                return
            } catch let error as UserDBError {
                guard case .locked = error else { throw error }
                if attempt == attempts { break }
                await sleep(.seconds(1))
            }
        }
        throw UserDBError.stillLocked(name)
    }

    /// 退出鼠须管，最多等 5 秒让它真的退出
    func stopSquirrel() async throws {
        guard squirrel.isRunning() else { return }
        try squirrel.quit()
        var waited = 0
        while squirrel.isRunning(), waited < 50 {
            await sleep(.milliseconds(100))
            waited += 1
        }
    }
}
