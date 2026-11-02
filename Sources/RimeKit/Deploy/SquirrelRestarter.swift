import Foundation

/// 重启鼠须管：别的软件把输入法弄出问题时用。只换进程，不碰配置，也不重新部署
public struct SquirrelRestarter: Sendable {
    let squirrel: any SquirrelControlling
    let sleep: @Sendable (Duration) async -> Void

    public init(squirrel: any SquirrelControlling,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.squirrel = squirrel
        self.sleep = sleep
    }

    /// 先普通退出，卡住了再强制退出，然后启动，确认进程起来了
    public func restart() async throws {
        if squirrel.isRunning() {
            try squirrel.quit()
            if await !waitUntil({ !squirrel.isRunning() }) {
                try squirrel.forceQuit()
                guard await waitUntil({ !squirrel.isRunning() }) else { throw SquirrelError.stillRunning }
            }
        }
        try squirrel.launch()
        guard await waitUntil({ squirrel.isRunning() }) else { throw SquirrelError.notStarted }
    }

    /// 最多等 5 秒
    func waitUntil(_ condition: () -> Bool) async -> Bool {
        var waited = 0
        while !condition() {
            guard waited < 50 else { return false }
            await sleep(.milliseconds(100))
            waited += 1
        }
        return true
    }
}
