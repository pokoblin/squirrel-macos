import Foundation
import Testing
@testable import RimeKit

@Suite struct UnzipperTests {
    @Test func 解开后太大的不解压() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let content = dir.url.appending(path: "c", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 10_000).write(to: content.appending(path: "big.txt"))
        let zip = dir.url.appending(path: "x.zip")
        try Zipper().zip(content, to: zip)
        #expect(throws: UnzipError.self) {
            try Unzipper(maxBytes: 1_000).unzip(zip, into: dir.url.appending(path: "out"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.url.appending(path: "out/big.txt").path))
        try Unzipper(maxBytes: 100_000).unzip(zip, into: dir.url.appending(path: "ok"))   // 没超就照常解
    }
}
