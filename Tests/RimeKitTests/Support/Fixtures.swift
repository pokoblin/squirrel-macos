import Foundation
@testable import RimeKit

/// 测试用的清单：base（Release 附件）和 app（按分支下载，依赖 base）
enum Fixtures {
    static let catalogJSON = """
    {"formatVersion":1,"packages":[
     {"id":"base","name":"基础","summary":"s","license":"MIT","homepage":"https://example.com/base",
      "source":{"type":"githubReleaseAsset","repo":"o/base","tag":"t","asset":"base.zip"},
      "anchor":"base.schema.yaml","include":["*.schema.yaml","dicts/**"],"exclude":["dicts/skip.txt"],
      "requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"],
      "schemas":[{"id":"base","name":"基础","category":"pinyin"}],"dependencies":[]},
     {"id":"app","name":"应用","summary":"s","license":"MIT","homepage":"https://example.com/app",
      "source":{"type":"githubBranch","repo":"o/app","branch":"main"},
      "anchor":"app.schema.yaml","include":["*.schema.yaml"],"exclude":[],
      "requiredFiles":["app.schema.yaml"],
      "schemas":[{"id":"app","name":"应用","category":"wubi"}],"dependencies":["base"]}
    ]}
    """

    static func catalog() throws -> Catalog {
        try Catalog.decode(Data(catalogJSON.utf8))
    }

    /// 把清单里的一段文字换掉（这段文字必须正好出现一次），用来造出各种有问题的清单
    static func catalogData(replacing old: String, with new: String) -> Data {
        precondition(catalogJSON.components(separatedBy: old).count == 2, "要替换的文字必须正好出现一次：\(old)")
        return Data(catalogJSON.replacingOccurrences(of: old, with: new).utf8)
    }

    // MARK: GitHub 接口

    static let baseReleaseURL = URL(string: "https://api.github.com/repos/o/base/releases/tags/t")!
    static let baseZipURL = URL(string: "https://example.com/dl/base.zip")!
    static let appCommitURL = URL(string: "https://api.github.com/repos/o/app/commits/main")!

    static func appZipURL(_ sha: String) -> URL {
        URL(string: "https://codeload.github.com/o/app/zip/\(sha)")!
    }

    /// assets: (附件名, 下载地址, 更新时间)
    static func releaseJSON(assets: [(String, URL, String)]) -> Data {
        let items = assets.map { name, url, updated in
            #"{"name":"\#(name)","browser_download_url":"\#(url.absoluteString)","updated_at":"\#(updated)","size":1}"#
        }
        return Data(#"{"tag_name":"t","assets":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    static func commitJSON(sha: String) -> Data {
        Data(#"{"sha":"\#(sha)","commit":{"message":"x"}}"#.utf8)
    }

    // MARK: 测试 zip

    /// base：没有顶层目录；有一个要排除的文件、一个不该装的 README
    static func baseZip() throws -> Data {
        try ZipFixture.make([
            "base.schema.yaml": "base",
            "dicts/a.dict.yaml": "a",
            "dicts/sub/b.dict.yaml": "b",
            "dicts/skip.txt": "skip",
            "README.md": "readme",
        ], topFolder: nil)
    }

    /// app：有顶层目录 app-<sha>/（像 codeload 的 zip）
    static func appZip(sha: String) throws -> Data {
        try ZipFixture.make(["app.schema.yaml": "app", "notes.txt": "n"], topFolder: "app-\(sha)")
    }

    /// 把 base 和 app 的接口、下载地址都设置好
    static func stubAll(_ http: FakeHTTPClient, baseVersion: String = "2026-10-05T13:38:43Z", appSHA: String = "abc123") throws {
        http.stub(baseReleaseURL, .success(releaseJSON(assets: [("base.zip", baseZipURL, baseVersion)])))
        http.stub(baseZipURL, .success(try baseZip()))
        http.stub(appCommitURL, .success(commitJSON(sha: appSHA)))
        http.stub(appZipURL(appSHA), .success(try appZip(sha: appSHA)))
    }

    static func paths(_ dir: TempDir) -> AppPaths {
        AppPaths(root: dir.url.appending(path: "data", directoryHint: .isDirectory))
    }
}
