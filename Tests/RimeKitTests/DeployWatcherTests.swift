import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployWatcherTests {
    @Test func 读部署时间() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let w = DeployFixtures.watcher(l)
        #expect(w.lastBuildTime() == nil)
        try FileManager.default.createDirectory(at: l.rimeDirectory, withIntermediateDirectories: true)
        try Data("var:\n  last_build_time: 1792040893\n  previously_selected_schema: x\n".utf8)
            .write(to: l.rimeDirectory.appending(path: "user.yaml"))
        #expect(w.lastBuildTime() == 1_792_040_893)
    }

    @Test func 部署时间变了就算完成并带上新的错误() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let squirrel = FakeSquirrel(locations: l, running: true)
        try squirrel.reload()   // 先部署一次，留下旧的部署时间和一行旧错误
        squirrel.errorLine = "E20261015 14:00:00.000000 0x1 a.cc:1] old"
        try squirrel.reload()
        let w = DeployFixtures.watcher(l)
        let previous = w.lastBuildTime()
        let snapshot = w.snapshot()
        squirrel.errorLine = "E20261015 14:00:01.000000 0x1 a.cc:1] dictionary 'nope' failed to compile."
        try squirrel.reload()
        let outcome = await w.wait(previousBuildTime: previous, since: snapshot)
        #expect(outcome == DeployOutcome(finished: true, errors: ["词库 nope 编译失败"]))
    }

    @Test func 一直没部署就超时() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let w = DeployFixtures.watcher(l)
        let outcome = await w.wait(previousBuildTime: nil, since: w.snapshot())
        #expect(outcome == DeployOutcome(finished: false, errors: []))
    }

    @Test func 原来没有user_yaml部署后出现了也算完成() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let w = DeployFixtures.watcher(l)
        let snapshot = w.snapshot()
        try FakeSquirrel(locations: l, running: false).launch()
        #expect(await w.wait(previousBuildTime: nil, since: snapshot).finished)
    }
}
