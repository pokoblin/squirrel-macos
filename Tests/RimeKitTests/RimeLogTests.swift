import Foundation
import Testing
@testable import RimeKit

@Suite struct RimeLogTests {
    let sample = """
    WARNING: Logging before InitGoogleLogging() is written to STDERR
    I20261015 14:07:26.214000 0x1 deployer.cc:1] start
    W20261015 14:07:26.214100 0x1 config.cc:1] nonexistent config file 'x'.
    E20261015 14:07:26.215025 0x1f65a7f80 dict_compiler.cc:115] neither nope.dict.yaml nor nope.table.bin exists.
    E20261015 14:07:26.215036 0x1f65a7f80 deployment_tasks.cc:376] dictionary 'nope' failed to compile.
    E20261015 14:07:26.230461 0x1f65a7f80 config_data.cc:78] Error parsing YAML "/tmp/x/demo.custom.yaml": something
    E20261015 14:07:26.231144 0x1f65a7f80 deployment_tasks.cc:338] invalid schema definition in '/tmp/x/demo.schema.yaml'.
    E20261015 14:07:26.231200 0x1f65a7f80 lua.cc:1] something odd
    E20261015 14:07:26.231300 0x1f65a7f80 deployment_tasks.cc:376] dictionary 'nope' failed to compile.
    """

    @Test func 只挑出E开头的日志行() {
        let lines = RimeLog.errorLines(sample)
        #expect(lines.count == 6)
        #expect(lines.allSatisfy { $0.hasPrefix("E2026") })
    }

    @Test func 翻译成白话去重保持顺序() {
        #expect(RimeLog.explain(RimeLog.errorLines(sample)) == [
            "找不到词库 nope（缺少 nope.dict.yaml）",
            "词库 nope 编译失败",
            "demo.custom.yaml 的格式不对（不是合法的 YAML）",
            "方案文件 demo.schema.yaml 的内容不对",
            "Rime 报错：something odd",
        ])
    }
}

/// 用宿主机鼠须管的 rime_deployer 编译临时目录（只读使用）
@Suite(.enabled(if: RimeTools.installed))
struct DeployerCompilerTests {
    func make(_ dir: TempDir, schemaDictionary: String = "demo", badPatch: Bool = false) throws -> URL {
        let d = dir.url.appending(path: "rime")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data("patch:\n  schema_list:\n    - schema: demo\n".utf8).write(to: d.appending(path: "default.custom.yaml"))
        let schema = "schema:\n  schema_id: demo\n  name: demo\nengine:\n  processors: [speller, express_editor]\n  segmentors: [abc_segmentor]\n  translators: [table_translator]\nspeller:\n  alphabet: abc\ntranslator:\n  dictionary: \(schemaDictionary)\n"
        try Data(schema.utf8).write(to: d.appending(path: "demo.schema.yaml"))
        try Data("---\nname: demo\nversion: \"1\"\n...\n你\ta\n".utf8).write(to: d.appending(path: "demo.dict.yaml"))
        if badPatch {
            try Data("patch:\n  \"translator/dictionary\": [1, 2\n".utf8).write(to: d.appending(path: "demo.custom.yaml"))
        }
        return d
    }

    @Test func 正常的能编译() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let report = try DeployerCompiler(locations: .default).compile(try make(dir))
        #expect(report == CompileReport(succeeded: true, errors: []))
    }

    @Test func 缺词库时失败() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let report = try DeployerCompiler(locations: .default).compile(try make(dir, schemaDictionary: "nope"))
        #expect(!report.succeeded)
        #expect(RimeLog.explain(report.errors).contains("找不到词库 nope（缺少 nope.dict.yaml）"))
    }

    @Test func 补丁写坏时退出码是0也算失败() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let report = try DeployerCompiler(locations: .default).compile(try make(dir, badPatch: true))
        #expect(!report.succeeded)
        #expect(RimeLog.explain(report.errors) == ["demo.custom.yaml 的格式不对（不是合法的 YAML）"])
    }
}
