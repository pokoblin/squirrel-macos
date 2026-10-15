import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlCatalogTests {
    typealias C = TestCatalogs

    func context(_ http: FakeHTTPClient, _ dir: TempDir, stdin: Data = Data()) throws -> (Rimectl.Context, Output) {
        let output = Output(echo: false)
        var ctx = Rimectl.Context(http: http, retry: .immediate, catalog: { try Catalog.decode(C.json(serial: 10)) },
                                  defaultPaths: Fixtures.paths(dir), output: output)
        ctx.catalogKeys = [C.publicKey]
        ctx.catalogURL = C.remote
        ctx.readStdin = { stdin }
        ctx.locations = try DeployFixtures.locations(dir)
        return (ctx, output)
    }

    @Test func show_说明用的是哪份() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = try context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["catalog", "show"], ctx) == 0)
        #expect(out.text.contains("内置方案清单（编号 10）"))
    }

    @Test func check_有更新以后所有命令都用新的() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let (ctx, out) = try context(http, dir)
        #expect(await Rimectl.run(["catalog", "check"], ctx) == 0)
        #expect(out.text.contains("新增方案：新方案"))
        #expect(await Rimectl.run(["catalog"], ctx) == 0)
        #expect(out.text.contains("extra  新方案"))
    }

    @Test func check_签名不对() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11), signature: C.sign(Data("别的".utf8)))
        let (ctx, out) = try context(http, dir)
        #expect(await Rimectl.run(["catalog", "check"], ctx) == 1)
        #expect(out.text.contains("签名不对"))
    }

    @Test func check_已经是最新的() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 10))
        let (ctx, out) = try context(http, dir)
        #expect(await Rimectl.run(["catalog", "check"], ctx) == 0)
        #expect(out.text.contains("方案清单已经是最新的"))
    }

    @Test func 签名和验证() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "catalog.json")
        let sig = dir.url.appending(path: "catalog.json.sig")
        try C.json(serial: 11).write(to: file)
        let (ctx, _) = try context(FakeHTTPClient(), dir, stdin: Data((C.keyPair.privateKey + "\n").utf8))
        #expect(await Rimectl.run(["catalog", "sign", file.path, "--out", sig.path], ctx) == 0)
        #expect(await Rimectl.run(["catalog", "verify", file.path, sig.path], ctx) == 0)
        try C.json(serial: 12).write(to: file)
        #expect(await Rimectl.run(["catalog", "verify", file.path, sig.path], ctx) == 1)
    }

    @Test func 发布前检查() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let new = dir.url.appending(path: "new.json")
        let old = dir.url.appending(path: "old.json")
        try C.json(serial: 11).write(to: new)
        try C.json(serial: 11).write(to: old)
        let (ctx, out) = try context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["catalog", "verify-source", new.path, old.path], ctx) == 1)
        #expect(out.text.contains("serial 要比上次发布的 11 大"))
        #expect(await Rimectl.run(["catalog", "verify-source", new.path, dir.url.appending(path: "none.json").path], ctx) == 0)
    }

    @Test func 生成密钥() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = try context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["catalog", "keygen"], ctx) == 0)
        let lines = out.text.split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("private ") })
        #expect(lines.contains { $0.hasPrefix("public ") })
    }

    @Test func 导入时不认识的方案先检查清单更新() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let (ctx, out) = try context(http, dir)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        _ = await Rimectl.run(["import", file.path, "--cache-only"], ctx)   // 本地没有 extra 的缓存，最后会失败
        #expect(out.text.contains("正在检查方案清单更新"))
        #expect(out.text.contains("方案清单更新了"))
        #expect(await Rimectl.run(["catalog", "show"], ctx) == 0)
        #expect(out.text.contains("在线方案清单（编号 11"))
    }
}
