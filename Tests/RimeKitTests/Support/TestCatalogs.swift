import Foundation
@testable import RimeKit

/// 在线方案清单测试用：在 Fixtures 的清单（base、app）上加 serial、改字段、签名、放到假网络上
enum TestCatalogs {
    /// Fixtures 的清单加上 serial，再做几处替换（每段要替换的文字必须正好出现一次）
    static func json(serial: Int, _ edits: [(String, String)] = []) -> Data {
        var text = Fixtures.catalogJSON.replacingOccurrences(
            of: #""formatVersion":1,"#, with: #""formatVersion":1,"serial":\#(serial),"#)
        for (old, new) in edits {
            precondition(text.components(separatedBy: old).count == 2, "要替换的文字必须正好出现一次：\(old)")
            text = text.replacingOccurrences(of: old, with: new)
        }
        return Data(text.utf8)
    }

    /// 给 app 包加字段，例如 app(#""deprecated":true"#)
    static func app(_ fields: String) -> (String, String) {
        (#""source":{"type":"githubBranch""#, fields + #","source":{"type":"githubBranch""#)
    }

    /// 给 base 包加字段
    static func base(_ fields: String) -> (String, String) {
        (#""source":{"type":"githubReleaseAsset""#, fields + #","source":{"type":"githubReleaseAsset""#)
    }

    /// 再加一个没有依赖的包 extra（方案 extra「新方案」）。source 的键故意换了顺序，不和 app()/base() 的替换冲突
    static let extraPackage = (#""dependencies":["base"]}"#, #"""
    "dependencies":["base"]},
     {"id":"extra","name":"新方案包","summary":"s","license":"MIT","homepage":"https://example.com/extra",
      "source":{"repo":"o/extra","type":"githubBranch","branch":"main"},
      "anchor":"extra.schema.yaml","include":["*.schema.yaml"],"exclude":[],
      "requiredFiles":["extra.schema.yaml"],
      "schemas":[{"id":"extra","name":"新方案","category":"other"}],"dependencies":[]}
    """#)

    static let keyPair = CatalogSignature.generateKeyPair()
    static var publicKey: Data { Data(base64Encoded: keyPair.publicKey)! }
    static var privateKey: Data { Data(base64Encoded: keyPair.privateKey)! }
    static let remote = URL(string: "https://example.com/catalog/v1/catalog.json")!

    static func sign(_ data: Data) -> Data {
        try! CatalogSignature.sign(data, privateKey: privateKey)
    }

    /// 假网络上放好在线清单和签名（signature 不给就用正确的）
    static func serve(_ http: FakeHTTPClient, _ data: Data, signature: Data? = nil) {
        http.stub(remote, .success(data))
        http.stub(CatalogStore.signatureURL(remote), .success(signature ?? sign(data)))
    }

    /// 内置清单默认是 serial 10 的 Fixtures 清单
    static func store(_ paths: AppPaths, _ http: FakeHTTPClient = FakeHTTPClient(),
                      builtIn: Data = json(serial: 10), appVersion: String = "0.2.0") -> CatalogStore {
        CatalogStore(paths: paths, http: http, retry: .immediate, builtIn: { try Catalog.decode(builtIn) },
                     keys: [publicKey], remote: remote, appVersion: AppVersion(appVersion)!)
    }

    /// 直接往缓存里放一份清单（模拟上次拉到的）
    static func cache(_ paths: AppPaths, _ data: Data, signature: Data? = nil) throws {
        try FileManager.default.createDirectory(at: paths.catalogCache, withIntermediateDirectories: true)
        try data.write(to: paths.catalogCache.appending(path: "catalog.json"))
        try (signature ?? sign(data)).write(to: paths.catalogCache.appending(path: "catalog.json.sig"))
    }
}
