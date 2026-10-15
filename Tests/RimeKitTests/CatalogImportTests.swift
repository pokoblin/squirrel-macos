import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogImportTests {
    typealias C = TestCatalogs

    actor Counter {
        var count = 0
        func bump() { count += 1 }
    }

    @Test func 认识的方案不联网() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["base"], in: dir.url)
        let opened = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                                 into: dir.url.appending(path: "work"))
        #expect(opened.updated == nil)
        #expect(opened.archive.manifest.settings.schemas == ["base"])
        #expect(http.callCount(C.remote) == 0)
    }

    @Test func 不认识的方案先检查更新再打开() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        let counter = Counter()
        let opened = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                                 into: dir.url.appending(path: "work"), checking: { await counter.bump() })
        #expect(opened.updated?.catalog.serial == 11)
        #expect(opened.archive.manifest.settings.schemas == ["extra"])
        #expect(await counter.count == 1)
        #expect(try store.effective().catalog.package("extra") != nil)
    }

    @Test func 更新了还是不认识() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11))
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        do {
            _ = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                            into: dir.url.appending(path: "work"))
            Issue.record("应该报错")
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("extra"))
        }
    }

    @Test func 清单已经是最新的() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 10))
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        do {
            _ = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                            into: dir.url.appending(path: "work"))
            Issue.record("应该报错")
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("方案清单已经是最新的"))
        }
    }

    @Test func 连不上时说清楚() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let store = C.store(Fixtures.paths(dir), FakeHTTPClient())
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        do {
            _ = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                            into: dir.url.appending(path: "work"))
            Issue.record("应该报错")
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("没拉到方案清单"))
            #expect(TransferError.unknownToCatalog(message).description.hasSuffix("请更新应用"))
        }
    }
}
