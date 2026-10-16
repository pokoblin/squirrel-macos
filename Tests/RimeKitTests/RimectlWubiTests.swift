import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

/// rimectl wubi：缓存里放迷你极点五笔包，数据目录和 Rime 目录都在临时目录里
private struct WubiEnv {
    let dir: TempDir
    let paths: AppPaths
    let rime: URL
    let output: Output
    let context: Rimectl.Context

    /// enabled：设置里启用极点五笔；cached：缓存里放包
    init(enabled: Bool = true, cached: Bool = true) throws {
        dir = try TempDir()
        paths = Fixtures.paths(dir)
        rime = dir.url.appending(path: "rime", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
        if cached { _ = try WubiFixtures.makePackage(in: paths.packages) }
        if enabled { try SettingsStore(paths: paths).save(Settings(schemas: ["wubi86_jidian"])) }
        output = Output(echo: false)
        let catalog = try WubiFixtures.catalog()
        var context = Rimectl.Context(http: FakeHTTPClient(), retry: .immediate, catalog: { catalog },
                                      defaultPaths: paths, output: output)
        context.previewHelper = PreviewFixtures.helper
        self.context = context
    }

    func run(_ args: [String]) async -> Int32 {
        await Rimectl.run(["wubi"] + args + ["--rime-dir", rime.path, "--data-dir", paths.root.path], context)
    }

    var lines: [String] { output.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }

    var personalFile: URL { paths.personalDicts.appending(path: WubiFixtures.userName) }

    func writePersonal(_ text: String) throws {
        try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: personalFile)
    }

    func personalText() throws -> String { try String(contentsOf: personalFile, encoding: .utf8) }
}

@Suite struct RimectlWubiTests {
    // MARK: encode

    @Test func 编码每个词一行() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["encode", "仰泳", "张三丰"]) == 0)
        #expect(e.lines == ["仰泳\twqiy", "张三丰\txddh"])
    }

    @Test func 多个编码都打印() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["encode", "戈戈"]) == 0)
        let parts = e.lines[0].split(separator: "\t").map(String.init)
        try #require(parts.count == 2)
        #expect(parts[0] == "戈戈")
        #expect(parts[1].split(separator: " ").count == 4)
    }

    @Test func 算不出() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["encode", "丁丁", "仰泳"]) == 0)
        #expect(e.lines == ["丁丁\t算不出：丁", "仰泳\twqiy"])
    }

    // MARK: list

    @Test func 列出带权重和总数() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t15\n")
        #expect(await e.run(["list"]) == 0)
        #expect(e.lines == ["分组词条\twxyt\t-", "甲乙\twqiy\t15", "共 2 个"])
    }

    @Test func 没写编码的显示自动算的() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n张三丰\n丁丁\n")
        #expect(await e.run(["list"]) == 0)
        #expect(e.lines == ["分组词条\twxyt\t-", "张三丰\txddh（自动）\t-", "丁丁\t算不出\t-", "共 3 个"])
    }

    // MARK: add

    @Test func 加词自动编码() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "张三丰"]) == 0)
        #expect(e.lines[0] == "已加入：张三丰 xddh（排第 1 个）")
        #expect(e.output.text.contains("运行 rimectl apply 让它生效"))
        #expect(try e.personalText().contains("张三丰\txddh"))
        // 不碰 Rime 目录
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.rime.path).isEmpty)
    }

    @Test func 加词排在最后不写权重() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "甲乙", "wqiy"]) == 0)
        #expect(e.lines[0] == "已加入：甲乙 wqiy（排第 3 个）")
        #expect(try e.personalText().hasSuffix("甲乙\twqiy\n"))
    }

    @Test func 加词指定位置() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        // wqiy 下原来是 你(20)、仰泳(10)：排第 1 个 → 权重 30
        #expect(await e.run(["add", "甲乙", "wqiy", "--position", "1"]) == 0)
        #expect(e.lines[0] == "已加入：甲乙 wqiy（排第 1 个）")
        #expect(try e.personalText().contains("甲乙\twqiy\t30"))
    }

    @Test func 位置放不进去() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t11\n")   // 你20、甲乙11、仰泳10
        let before = try e.personalText()
        #expect(await e.run(["add", "丙丁", "wqiy", "--position", "3"]) == 1)
        #expect(e.output.text.contains("这个位置放不进去"))
        #expect(try e.personalText() == before)
    }

    @Test func 加过的词退出码1() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "张三丰"]) == 0)
        #expect(await e.run(["add", "张三丰"]) == 1)
        #expect(e.output.text.contains("已经加过了"))
    }

    @Test func 没写编码的词按自动编码查重() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n张三丰\n")
        let before = try e.personalText()
        #expect(await e.run(["add", "张三丰"]) == 1)
        #expect(e.output.text.contains("已经加过了"))
        #expect(await e.run(["add", "张三丰", "xddh"]) == 1)
        #expect(try e.personalText() == before)
    }

    @Test func 词里有制表符或换行不能加() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "甲\t乙", "wqiy"]) == 1)
        #expect(await e.run(["add", "甲\n乙", "wqiy"]) == 1)
        #expect(e.output.text.contains("不能含有制表符或换行"))
        #expect(!FileManager.default.fileExists(atPath: e.personalFile.path))
    }

    @Test func 主词库里有的退出码1() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "仰泳"]) == 1)
        #expect(e.output.text.contains("词库里已经有了"))
        #expect(!FileManager.default.fileExists(atPath: e.personalFile.path))
    }

    @Test func 算不出编码要手填() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "丁丁"]) == 1)
        #expect(e.output.text.contains("算不出"))
        #expect(await e.run(["add", "丁丁", "ABC"]) == 1)
        #expect(await e.run(["add", "丁丁", "abcde"]) == 1)
        #expect(!FileManager.default.fileExists(atPath: e.personalFile.path))
    }

    @Test func 位置参数不对是用法错误() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["add", "张三丰", "--position", "0"]) == 2)
        #expect(await e.run(["add", "张三丰", "--position", "x"]) == 2)
        #expect(await e.run(["add", "张三丰", "--position"]) == 2)
    }

    // MARK: remove

    @Test func 删词() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        _ = await e.run(["add", "张三丰"])
        #expect(await e.run(["remove", "张三丰"]) == 0)
        #expect(e.output.text.contains("删掉 1 条"))
        #expect(!(try e.personalText().contains("张三丰")))
        #expect(try e.personalText().contains("分组词条"))
    }

    @Test func 删词指定编码只删这一条() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\n甲乙\tabcd\n")
        #expect(await e.run(["remove", "甲乙", "abcd"]) == 0)
        let text = try e.personalText()
        #expect(text.contains("甲乙\twqiy"))
        #expect(!text.contains("abcd"))
    }

    @Test func 删词指定编码也匹配没写编码的词() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n张三丰\n")
        #expect(await e.run(["remove", "张三丰", "abcd"]) == 1)   // 自动编码是 xddh
        #expect(await e.run(["remove", "张三丰", "xddh"]) == 0)
        #expect(!(try e.personalText().contains("张三丰")))
    }

    @Test func 没找到退出码1() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["remove", "不存在"]) == 1)
        #expect(e.output.text.contains("没找到"))
        #expect(!FileManager.default.fileExists(atPath: e.personalFile.path))
    }

    // MARK: import

    @Test func 导入加可以加的行() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        let file = e.dir.url.appending(path: "words.txt")
        try Data("张三丰\n仰泳\n丁丁\n# 注释\n甲乙\twqiy\t30\n".utf8).write(to: file)
        #expect(await e.run(["import", file.path]) == 0)
        #expect(e.lines[0] == "加入 2 个")
        #expect(e.lines.contains("第 2 行：词库里已经有了"))
        #expect(e.lines.contains { $0.hasPrefix("第 3 行：算不出") })
        #expect(e.output.text.contains("运行 rimectl apply 让它生效"))
        let text = try e.personalText()
        #expect(text.contains("张三丰\txddh"))
        #expect(text.contains("甲乙\twqiy\t30"))
        #expect(!text.contains("丁丁"))
    }

    @Test func 导入按自动编码查重() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n张三丰\n")
        let file = e.dir.url.appending(path: "words.txt")
        try Data("张三丰\n甲乙\twqiy\n张三丰\txddh\n".utf8).write(to: file)
        #expect(await e.run(["import", file.path]) == 0)
        #expect(e.lines[0] == "加入 1 个")
        #expect(e.lines.contains("第 1 行：已经加过了"))
        #expect(e.lines.contains("第 3 行：和前面的行重复"))
        #expect(try e.personalText().components(separatedBy: "张三丰").count == 2)
    }

    @Test func 导入没有可加的不写文件() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        let file = e.dir.url.appending(path: "words.txt")
        try Data("仰泳\n".utf8).write(to: file)
        #expect(await e.run(["import", file.path]) == 0)
        #expect(e.lines[0] == "加入 0 个")
        #expect(!e.output.text.contains("rimectl apply"))
        #expect(!FileManager.default.fileExists(atPath: e.personalFile.path))
    }

    @Test func 导入文件读不了() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run(["import", e.dir.url.appending(path: "nope.txt").path]) == 1)
        #expect(await e.run(["import"]) == 2)
    }

    // MARK: 出错

    @Test func 没启用极点五笔() async throws {
        let e = try WubiEnv(enabled: false); defer { e.dir.remove() }
        #expect(await e.run(["list"]) == 1)
        #expect(e.output.text.contains("先在「方案」页启用极点五笔"))
        #expect(await e.run(["add", "张三丰"]) == 1)
        #expect(!FileManager.default.fileExists(atPath: e.personalFile.path))
    }

    @Test func 没有缓存包() async throws {
        let e = try WubiEnv(cached: false); defer { e.dir.remove() }
        #expect(await e.run(["encode", "仰泳"]) == 1)
        #expect(e.output.text.contains("还没下载极点五笔，先应用一次改动"))
    }

    @Test func 子命令不对是用法错误() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        #expect(await e.run([]) == 2)
        #expect(await e.run(["nope"]) == 2)
        #expect(await e.run(["encode"]) == 2)
        #expect(await e.run(["add"]) == 2)
    }
}

/// check 要用宿主机的鼠须管编译、用辅助程序试打
@Suite(.enabled(if: RimeTools.installed)) struct RimectlWubiCheckTests {
    @Test(.timeLimit(.minutes(2))) func 检查每个词() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        // 60 个权重 100 的占位词把末尾的词挤到五页以外，打不出来
        let fillers = (1...60).map { "占位\($0)\twqiy\t100" }.joined(separator: "\n")
        try e.writePersonal(WubiFixtures.userDict + "\n" + fillers + "\n末尾\twqiy\t1\n甲乙\twqiy\t300\n")
        #expect(await e.run(["check"]) == 1)
        #expect(e.lines.contains("分组词条\twxyt\t第 1 页第 1 个"), "\(e.output.text)")
        #expect(e.lines.contains("甲乙\twqiy\t第 1 页第 1 个"), "\(e.output.text)")
        #expect(e.lines.contains("末尾\twqiy\t打不出来"), "\(e.output.text)")
        // 副本用完删掉
        let left = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(left.isEmpty)
    }

    @Test(.timeLimit(.minutes(2))) func 位置对的不报不一样() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        // 个人词库里的词排在 你(20) 前面，索引和引擎一致，应该是预期的位置
        try e.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t30\n")
        #expect(await e.run(["check"]) == 0)
        #expect(e.lines.contains("甲乙\twqiy\t第 1 页第 1 个"), "\(e.output.text)")
        #expect(!e.output.text.contains("位置和选的不一样"))
    }

    @Test(.timeLimit(.minutes(2))) func 没写编码的用算出来的编码检查() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n张三丰\n")
        #expect(await e.run(["check"]) == 0)
        #expect(e.lines.contains("张三丰\txddh\t第 1 页第 1 个"), "\(e.output.text)")
    }

    /// 算不出编码又没写编码的词，Rime 编译就会失败：检查把翻译过的错误打印出来，副本照样删掉
    @Test(.timeLimit(.minutes(2))) func 编译失败说清楚() async throws {
        let e = try WubiEnv(); defer { e.dir.remove() }
        try e.writePersonal(WubiFixtures.userDict + "\n丁丁\n")
        #expect(await e.run(["check"]) == 1)
        #expect(e.output.text.contains("编译试打用的配置失败了"), "\(e.output.text)")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(left.isEmpty)
    }

    @Test func 没启用极点五笔不编译() async throws {
        let e = try WubiEnv(enabled: false); defer { e.dir.remove() }
        #expect(await e.run(["check"]) == 1)
        #expect(e.output.text.contains("先在「方案」页启用极点五笔"))
    }
}
