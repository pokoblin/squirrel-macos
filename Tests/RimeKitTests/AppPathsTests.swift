import Foundation
import Testing
@testable import RimeKit

@Suite struct AppPathsTests {
    @Test func 默认目录在应用支持目录下() {
        let path = AppPaths.default.root.path
        #expect(path.hasSuffix("/Library/Application Support/squirrel-macos"))
    }

    @Test func 子目录都在根目录下() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/x", isDirectory: true))
        #expect(paths.packages.path == "/tmp/x/packages")
        #expect(paths.staging.path == "/tmp/x/staging")
        #expect(paths.settingsFile.path == "/tmp/x/settings.json")
        #expect(paths.personalDicts.path == "/tmp/x/personal/dicts")
        #expect(paths.personalPhrases.path == "/tmp/x/personal/phrases.txt")
        #expect(paths.ledgerFile.path == "/tmp/x/ledger.json")
        #expect(paths.backups.path == "/tmp/x/backups")
        #expect(paths.lockFile.path == "/tmp/x/lock")
    }

    @Test func 打开应用时清理暂存区里的旧东西() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let fm = FileManager.default
        let old = paths.staging.appending(path: "fetch-old", directoryHint: .isDirectory)
        let fresh = paths.staging.appending(path: "fetch-new", directoryHint: .isDirectory)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        let now = Date()
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-7_200)], ofItemAtPath: old.path)
        paths.cleanStaleStaging(olderThan: 3_600, now: now)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: fresh.path))
    }

    @Test func 打开应用时试打副本不管新旧都删() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let fm = FileManager.default
        let preview = paths.staging.appending(path: "preview-ABC", directoryHint: .isDirectory)
        let fresh = paths.staging.appending(path: "fetch-new", directoryHint: .isDirectory)
        try fm.createDirectory(at: preview, withIntermediateDirectories: true)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        paths.cleanStaleStaging()
        #expect(fm.fileExists(atPath: preview.path))   // 默认还是只删旧的
        paths.cleanStaleStaging(includingPreviews: true)
        #expect(!fm.fileExists(atPath: preview.path))
        #expect(fm.fileExists(atPath: fresh.path))
    }
}
