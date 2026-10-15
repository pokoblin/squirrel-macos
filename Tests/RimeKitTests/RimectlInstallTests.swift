import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlInstallTests {
    struct Env {
        let dir: TempDir
        let locations: RimeLocations
        let input: FakeInputSource
        let squirrel: FakeSquirrel
        let privileged: FakePrivileged
        let output: Output
        let context: Rimectl.Context
        func run(_ args: [String]) async -> Int32 { await Rimectl.run(args, context) }
    }

    func env(installed: String? = nil, input: InputSourceState = InputSourceState(registered: true, enabled: false, selected: false)) throws -> Env {
        let dir = try TempDir()
        // 用 DeployFixtures 的假鼠须管（带 rime_deployer，activate 才认为装了）；没写 Info.plist 时版本为空，算没装
        let locations = try DeployFixtures.locations(dir)
        if let installed { try InstallFixtures.writeInfoPlist(app: locations.squirrelApp, version: installed) }
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: "abc")))
        http.stub(InstallFixtures.pkgURL("1.1.2"), .success(Data("pkg".utf8)))
        let fakeInput = FakeInputSource(input)
        let privileged = FakePrivileged(app: locations.squirrelApp, version: "1.1.2")
        let squirrel = FakeSquirrel(locations: locations, running: false)
        let output = Output(echo: false)
        let catalog = try Catalog.builtIn()
        let context = Rimectl.Context(
            http: http, retry: .immediate, catalog: { catalog }, defaultPaths: Fixtures.paths(dir), output: output,
            locations: locations, compiler: FakeCompiler(), squirrel: squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in },
            inputSource: fakeInput, privileged: privileged, verifier: FakeVerifier(), activationTimeout: 3)
        return Env(dir: dir, locations: locations, input: fakeInput, squirrel: squirrel, privileged: privileged, output: output, context: context)
    }

    @Test func install装上() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["install"]) == 0)
        #expect(e.output.text.contains("已安装鼠须管 1.1.2"))
        #expect(await e.run(["install"]) == 0)
        #expect(e.output.text.contains("已经装了鼠须管 1.1.2"))
    }

    @Test func install被取消() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.privileged.error = .cancelled
        #expect(await e.run(["install"]) == 1)
        #expect(e.output.text.contains("你取消了授权"))
    }

    @Test func activate等用户添加() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        e.input.enableAfterPumps = 2
        #expect(await e.run(["activate"]) == 0)
        #expect(e.output.text.contains("已打开系统设置的键盘页"))
        #expect(e.output.text.contains("鼠须管可以用了"))
    }

    @Test func activate超时() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        #expect(await e.run(["activate", "--timeout", "2"]) == 1)
        #expect(e.output.text.contains("还没看到鼠须管被添加"))
    }

    @Test func activate重新注册输入源() async throws {
        let e = try env(installed: "1.1.2", input: InputSourceState(registered: false, enabled: false, selected: false))
        defer { e.dir.remove() }
        let input = e.input
        e.squirrel.onRegister = { input.changeOnNextPump(to: InputSourceState(registered: true, enabled: true, selected: false)) }
        #expect(await e.run(["activate"]) == 0)
        #expect(e.output.text.contains("系统里没有鼠须管的输入源，正在重新注册"))
        #expect(e.output.text.contains("鼠须管可以用了"))
    }

    @Test func activate重新注册也没用() async throws {
        let e = try env(installed: "1.1.2", input: InputSourceState(registered: false, enabled: false, selected: false))
        defer { e.dir.remove() }
        #expect(await e.run(["activate"]) == 1)
        #expect(e.output.text.contains("重新注册了鼠须管的输入源，系统里还是没有"))
    }

    @Test func doctor() async throws {
        let e = try env(installed: nil); defer { e.dir.remove() }
        #expect(await e.run(["doctor", "--offline"]) == 1)
        #expect(e.output.text.contains("[问题] 鼠须管：还没有安装"))
        #expect(e.output.text.contains("→ 运行 rimectl install"))
    }
}
