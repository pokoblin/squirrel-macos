import Foundation
import Testing
@testable import RimeKit

@Suite struct DeploySymlinkTests {
    @Test func Rime目录本身是符号链接时也能列出配置文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fm = FileManager.default
        let real = dir.url.appending(path: "Dropbox/Rime", directoryHint: .isDirectory)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: real.appending(path: "default.custom.yaml"))
        let link = dir.url.appending(path: "Rime")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(try RimeFiles.configFiles(in: link) == ["default.custom.yaml"])
    }

    @Test func Rime目录是符号链接时覆盖前的备份不是空的() async throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        let fm = FileManager.default
        let real = e.dir.url.appending(path: "Dropbox/Rime", directoryHint: .isDirectory)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: real.appending(path: "default.custom.yaml"))
        try fm.createSymbolicLink(at: e.rime, withDestinationURL: real)
        guard case .applied(let report) = try await e.deployer().apply(
            try e.input(Settings(schemas: ["wb"])), options: ApplyOptions(overwriteExternalChanges: true)) else {
            Issue.record("应该写入成功")
            return
        }
        #expect(report.backup.files == ["default.custom.yaml"])
        #expect(report.backup.permanent)
    }
}
