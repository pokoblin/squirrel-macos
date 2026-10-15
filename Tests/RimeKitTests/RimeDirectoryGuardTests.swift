import Foundation
import Testing
@testable import RimeKit

@Suite struct RimeDirectoryGuardTests {
    func home(_ dir: TempDir, rime: Bool) throws -> URL {
        let home = dir.url.appending(path: "home", directoryHint: .isDirectory)
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        if rime {
            try FileManager.default.createDirectory(at: library.appending(path: "Rime/build"), withIntermediateDirectories: true)
        }
        return home
    }

    @Test func 认出Rime目录和它里面的目录() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: true)
        let homes = [home.path]
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime"), homes: homes))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime/build"), homes: homes))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime/new/deep"), homes: homes))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/rime"), homes: homes))
    }

    @Test func Rime目录还不存在时也认得出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: false)
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime"), homes: [home.path]))
    }

    @Test func 符号链接指过去也认得出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: true)
        let link = dir.url.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appending(path: "Library/Rime"))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(link.appending(path: "x"), homes: [home.path]))
    }

    @Test func 普通目录和别处叫Rime的目录不算() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: true)
        let homes = [home.path]
        #expect(!RimeDirectoryGuard.isInsideRealRimeDirectory(dir.url.appending(path: "out"), homes: homes))
        #expect(!RimeDirectoryGuard.isInsideRealRimeDirectory(dir.url.appending(path: "copy/Rime"), homes: homes))
        #expect(!RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Other"), homes: homes))
    }

    @Test func 没有家目录可比时当作是() {
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(URL(fileURLWithPath: "/tmp/x"), homes: []))
    }

    @Test func 真实家目录的firmlink写法也认得出() {
        // 只读判断，不写任何东西
        let real = NSHomeDirectory() + "/Library/Rime"
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(URL(fileURLWithPath: real)))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(URL(fileURLWithPath: "/System/Volumes/Data" + real)))
    }
}
