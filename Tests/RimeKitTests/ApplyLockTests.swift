import Foundation
import Testing
@testable import RimeKit

@Suite struct ApplyLockTests {
    @Test func 同时只能有一个() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        var first: ApplyLock? = try ApplyLock.acquire(paths)
        #expect(throws: ApplyError.busy) { try ApplyLock.acquire(paths) }
        _ = first
        first = nil
        _ = try ApplyLock.acquire(paths)
    }

    @Test func 错误信息是中文() {
        #expect(ApplyError.busy.description == "正在应用改动，请稍等再试")
    }

    @Test func 打不开锁文件时不说正在应用() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.lockFile, withIntermediateDirectories: true)   // 锁文件的位置是个目录：打不开
        #expect {
            _ = try ApplyLock.acquire(paths)
        } throws: { error in
            "\(error)".contains("锁文件") && !"\(error)".contains("正在应用")
        }
    }

}
