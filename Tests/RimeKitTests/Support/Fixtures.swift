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
}
