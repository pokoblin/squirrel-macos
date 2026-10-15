import Foundation
import Testing
@testable import RimeKit

@Suite struct RimeFilesTests {
    @Test func 认出Rime自己的运行文件() {
        for path in ["build/default.yaml", "build", "sync/abc/rime_ice.userdb.txt", "installation.yaml", "user.yaml",
                     "rime_ice.userdb", "rime_ice.userdb/LOCK", "x.userdb.txt", ".DS_Store", "cn_dicts/.DS_Store"] {
            #expect(RimeFiles.isRimeOwned(path), "\(path)")
        }
        for path in ["default.custom.yaml", "rime_ice.schema.yaml", "cn_dicts/8105.dict.yaml", "custom_phrase.txt", "lua/x.lua"] {
            #expect(!RimeFiles.isRimeOwned(path), "\(path)")
        }
    }

    @Test func 列出配置文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fm = FileManager.default
        for path in ["default.custom.yaml", "cn_dicts/8105.dict.yaml", "build/default.yaml", "user.yaml",
                     "rime_ice.userdb/LOCK", "sync/x/a.userdb.txt", ".DS_Store"] {
            let url = dir.url.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        try fm.createSymbolicLink(at: dir.url.appending(path: "link.yaml"), withDestinationURL: dir.url.appending(path: "default.custom.yaml"))
        try fm.createDirectory(at: dir.url.appending(path: "empty"), withIntermediateDirectories: true)
        #expect(try RimeFiles.configFiles(in: dir.url) == ["cn_dicts/8105.dict.yaml", "default.custom.yaml", "link.yaml"])
    }

    @Test func 目录不存在时是空的() throws {
        #expect(try RimeFiles.configFiles(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == [])
    }

    @Test func 默认位置() {
        let l = RimeLocations.default
        #expect(l.rimeDirectory.path.hasSuffix("/Library/Rime"))
        #expect(l.deployerBinary.path == "/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer")
        #expect(l.squirrelBinary.path == "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel")
        #expect(l.sharedSupport.path == "/Library/Input Methods/Squirrel.app/Contents/SharedSupport")
        #expect(l.logDirectory.path.hasSuffix("/rime.squirrel"))
    }
}
