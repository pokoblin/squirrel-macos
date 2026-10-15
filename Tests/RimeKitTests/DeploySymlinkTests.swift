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

@Suite struct DeployInnerSymlinkTests {
    @Test func 相对链接在暂存区里也能用() throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        let fm = FileManager.default
        try fm.createDirectory(at: e.rime, withIntermediateDirectories: true)
        let ext = e.dir.url.appending(path: "ext", directoryHint: .isDirectory)
        try fm.createDirectory(at: ext, withIntermediateDirectories: true)
        try Data("lua".utf8).write(to: ext.appending(path: "x.lua"))
        try fm.createSymbolicLink(atPath: e.rime.appending(path: "rel.lua").path, withDestinationPath: "../ext/x.lua")
        // 拼暂存区时，链接要换成它指向的真实内容（相对链接复制过去会断）
        let staged = e.dir.url.appending(path: "work/deeper/staged")   // 放深一层，相对链接原样复制过来就会断
        try Deployer.copy(e.rime.appending(path: "rel.lua"), to: staged.appending(path: "rel.lua"))
        #expect(try String(contentsOf: staged.appending(path: "rel.lua"), encoding: .utf8) == "lua")
    }

    @Test func 不能穿过指向外面的目录链接写文件() async throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        let fm = FileManager.default
        try fm.createDirectory(at: e.rime, withIntermediateDirectories: true)
        let outside = e.dir.url.appending(path: "dotfiles/cn", directoryHint: .isDirectory)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        // words 包要写 cn/a.dict.yaml，而 cn 是指向 Rime 目录外面的链接
        try fm.createSymbolicLink(at: e.rime.appending(path: "cn"), withDestinationURL: outside)
        let outcome = try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])),
                                                   options: ApplyOptions(overwriteExternalChanges: true))
        #expect(outcome == .externalChanges([.outsideRimeDirectory("cn/a.dict.yaml")]))
        #expect(try fm.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
