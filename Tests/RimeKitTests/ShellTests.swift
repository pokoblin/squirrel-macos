import Foundation
import Testing
@testable import RimeKit

@Suite struct ShellTests {
    @Test func 普通命令拿到输出和退出码() throws {
        let r = try Shell.run("/bin/sh", ["-c", "echo out; echo err 1>&2; exit 3"])
        #expect(r.status == 3)
        #expect(r.stdout == "out\n")
        #expect(r.stderr == "err\n")
    }

    @Test(.timeLimit(.minutes(1)))
    func 错误输出很多也不会卡住() throws {
        // 先往 stderr 写 300KB，再写 stdout。管道缓冲只有 64KB 左右，读法不对就会互相等死。
        let r = try Shell.run("/bin/sh", ["-c", "head -c 300000 /dev/zero | tr '\\000' x 1>&2; echo done"])
        #expect(r.status == 0)
        #expect(r.stdout == "done\n")
        #expect(r.stderr.count == 300_000)
    }
}
