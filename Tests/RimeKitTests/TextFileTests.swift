import Foundation
import Testing
@testable import RimeKit

@Suite struct TextFileTests {
    @Test func 不是UTF8时说是哪个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "custom_phrase.txt")
        try Data([0xC4, 0xE3, 0xBA, 0xC3]).write(to: file)   // GBK 的「你好」
        #expect {
            _ = try TextFile.read(file)
        } throws: { error in
            "\(error)".contains("custom_phrase.txt") && "\(error)".contains("UTF-8")
        }
    }
}
