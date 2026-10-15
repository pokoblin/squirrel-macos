import Foundation
import Testing
@testable import RimeKit

@Suite struct DoctorTests {
    func doctor(_ dir: TempDir, installed: String?, input: InputSourceState, running: Bool,
                latest: String? = nil) throws -> (Doctor, RimeLocations) {
        var l = try DeployFixtures.locations(dir)
        if installed == nil {
            l.squirrelApp = dir.url.appending(path: "None.app")
        } else {
            try InstallFixtures.writeInfoPlist(app: l.squirrelApp, version: installed!)
        }
        var source: SquirrelReleaseSource?
        if let latest {
            let http = FakeHTTPClient()
            http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: latest, digest: nil)))
            source = SquirrelReleaseSource(http: http, retry: .immediate)
        }
        let d = Doctor(paths: Fixtures.paths(dir), locations: l, inputSource: FakeInputSource(input),
                       squirrel: FakeSquirrel(locations: l, running: running), releaseSource: source)
        return (d, l)
    }

    @Test func 新电脑上什么都没有() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: nil, input: InputSourceState(registered: false, enabled: false, selected: false), running: false)
        let checks = await d.run()
        #expect(checks.map(\.name) == ["鼠须管", "设置"])
        #expect(checks[0] == DoctorCheck(name: "鼠须管", level: .problem, message: "还没有安装", hint: "运行 rimectl install"))
        #expect(checks[1].level == .warning)
    }

    @Test func 装了但还没在系统设置里添加() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: false, selected: false), running: false)
        let checks = await d.run()
        #expect(checks.first { $0.name == "输入法" } == DoctorCheck(
            name: "输入法", level: .problem, message: "还没有在系统设置里添加鼠须管", hint: "运行 rimectl activate"))
        #expect(checks.first { $0.name == "鼠须管进程" }?.level == .warning)
        #expect(checks.first { $0.name == "Rime 目录" }?.level == .warning)
    }

    @Test func 输入源从系统里丢了() async throws {
        // install --force 不一定有用（postinstall 认为已经注册过就跳过），activate 会重新注册
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: false, enabled: false, selected: false), running: true)
        let checks = await d.run()
        #expect(checks.first { $0.name == "输入法" } == DoctorCheck(
            name: "输入法", level: .problem, message: "系统里没有鼠须管的输入源", hint: "运行 rimectl activate（会重新注册输入源）"))
    }

    @Test func 一切正常() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, l) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: true, selected: true), running: true,
                                latest: "1.1.2")
        try FakeSquirrel(locations: l, running: true).reload()   // 留下 user.yaml（部署过）
        try SettingsStore(paths: Fixtures.paths(dir)).save(.starter(.rimeIce))
        try Ledger(entries: [:], appliedAt: Date(timeIntervalSince1970: 1_000)).save(Fixtures.paths(dir))
        let checks = await d.run()
        #expect(checks.allSatisfy { $0.level == .ok }, "\(checks)")
        #expect(checks.first { $0.name == "鼠须管" }?.message == "已安装 1.1.2（是最新版）")
    }

    @Test func 有新版本时提醒但不算问题() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.1", input: InputSourceState(registered: true, enabled: true, selected: true), running: true,
                                latest: "1.1.2")
        let check = await d.run().first { $0.name == "鼠须管" }
        #expect(check?.level == .ok)
        #expect(check?.message == "已安装 1.1.1（最新是 1.1.2，鼠须管会自己提示更新）")
    }

    @Test func 添加了但没选中() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: true, selected: false), running: true)
        #expect(await d.run().first { $0.name == "输入法" }?.level == .warning)
    }

    @Test func 有外部改动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, l) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: true, selected: true), running: true)
        try Ledger(entries: ["gone.yaml": LedgerEntry(sha256: "x", origin: "generated")], appliedAt: Date()).save(Fixtures.paths(dir))
        _ = l
        let check = await d.run().first { $0.name == "应用管理的配置" }
        #expect(check?.level == .warning)
        #expect(check?.message == "有 1 个文件在应用外被改过或删了")
    }
}
