import Foundation
import Testing
@testable import RimeKit

@Suite struct PreviewWorkspaceTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        var rime: URL { locations.rimeDirectory }

        func workspace(_ compiler: any RimeCompiler = FakeCompiler()) -> PreviewWorkspace {
            PreviewWorkspace(paths: paths, locations: locations, compiler: compiler)
        }

        func write(_ path: String, _ text: String, in base: URL? = nil) throws {
            let url = (base ?? rime).appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        /// 装好的 Rime 目录：配置、编译结果，加上不该复制的各种运行文件
        func populate(at base: URL? = nil) throws {
            try write("default.custom.yaml", "patch:\n  menu/page_size: 5\n", in: base)
            try write("build/default.yaml", "schema_list:\n  - schema: py\n", in: base)
            try write("build/py.schema.yaml", "schema:\n  schema_id: py\n  name: 测试拼音\n", in: base)
            try write("rime_ice.userdb/LOG", "x", in: base)
            try write("x.userdb.txt", "x", in: base)
            try write("sync/a", "x", in: base)
            try write("user.yaml", "x", in: base)
            try write("installation.yaml", "x", in: base)
            try write(".git/HEAD", "x", in: base)
        }

        func stagingIsEmpty() -> Bool {
            ((try? FileManager.default.contentsOfDirectory(atPath: paths.staging.path)) ?? []).isEmpty
        }
    }

    func env() throws -> Env {
        let dir = try TempDir()
        return Env(dir: dir, paths: Fixtures.paths(dir), locations: try DeployFixtures.locations(dir))
    }

    func exists(_ base: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: base.appending(path: path).path)
    }

    @Test func 当前生效带build不带输入习惯() throws {
        let e = try env(); defer { e.dir.remove() }
        try e.populate()
        let before = try FileManager.default.contentsOfDirectory(atPath: e.rime.path).sorted()
        let copy = try e.workspace().prepareCurrent()
        #expect(exists(copy.userDir, "default.custom.yaml") && exists(copy.userDir, "build/py.schema.yaml"))
        for gone in ["rime_ice.userdb", "x.userdb.txt", "sync", "user.yaml", "installation.yaml", ".git"] {
            #expect(!exists(copy.userDir, gone), "\(gone) 不该被复制")
        }
        #expect(copy.schemas == [PreviewSchema(id: "py", name: "测试拼音")])
        #expect(copy.root.path.hasPrefix(e.paths.staging.path) && copy.root.lastPathComponent.hasPrefix("preview-"))
        // 只读 Rime 目录，原来的东西一样不少
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.rime.path).sorted() == before)
        copy.remove()
        #expect(!FileManager.default.fileExists(atPath: copy.root.path))
    }

    @Test func Rime目录是符号链接() throws {
        let e = try env(); defer { e.dir.remove() }
        let real = e.dir.url.appending(path: "elsewhere/Rime", directoryHint: .isDirectory)
        try e.populate(at: real)
        try FileManager.default.createDirectory(at: e.rime.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: e.rime, withDestinationURL: real)
        let copy = try e.workspace().prepareCurrent(); defer { copy.remove() }
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: copy.userDir.path, isDirectory: &isDir) && isDir.boolValue)
        let type = try FileManager.default.attributesOfItem(atPath: copy.userDir.path)[.type] as? FileAttributeType
        #expect(type == .typeDirectory)
        #expect(exists(copy.userDir, "default.custom.yaml") && exists(copy.userDir, "build/default.yaml"))
    }

    @Test func 顶层的符号链接换成真实内容() throws {
        let e = try env(); defer { e.dir.remove() }
        try e.populate()
        try e.write("dots/my.custom.yaml", "patch: {}\n", in: e.dir.url)
        try FileManager.default.createSymbolicLink(at: e.rime.appending(path: "my.custom.yaml"),
                                                   withDestinationURL: e.dir.url.appending(path: "dots/my.custom.yaml"))
        let copy = try e.workspace().prepareCurrent(); defer { copy.remove() }
        let type = try FileManager.default.attributesOfItem(atPath: copy.userDir.appending(path: "my.custom.yaml").path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
    }

    @Test func 没部署过() throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "patch: {}\n")
        #expect(throws: PreviewError.notDeployed) { try e.workspace().prepareCurrent() }
        #expect(e.stagingIsEmpty())
        // Rime 目录整个不存在也一样
        let none = try env(); defer { none.dir.remove() }
        #expect(throws: PreviewError.notDeployed) { try none.workspace().prepareCurrent() }
        #expect(none.stagingIsEmpty())
    }

    @Test func 部署过但没有方案() throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("build/default.yaml", "schema_list: []\n")
        #expect(throws: PreviewError.noSchemas) { try e.workspace().prepareCurrent() }
        #expect(e.stagingIsEmpty())
    }

    @Test func 方案列表只留编译出来的() throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("build/default.yaml", "schema_list:\n  - schema: py\n  - schema: gone\n  - schema: wb\n  - schema: py\n")
        try e.write("build/py.schema.yaml", "schema:\n  schema_id: py\n  name: 测试拼音\n")
        try e.write("build/wb.schema.yaml", "schema:\n  schema_id: wb\n")
        #expect(try PreviewWorkspace.schemas(in: e.rime) == [PreviewSchema(id: "py", name: "测试拼音"), PreviewSchema(id: "wb", name: "wb")])
    }

    @Test func 没有方案() throws {
        let e = try env(); defer { e.dir.remove() }
        // default.yaml 不存在
        #expect(throws: PreviewError.noSchemas) { try PreviewWorkspace.schemas(in: e.rime) }
        // schema_list 为空
        try e.write("build/default.yaml", "schema_list: []\n")
        #expect(throws: PreviewError.noSchemas) { try PreviewWorkspace.schemas(in: e.rime) }
        // 列表里的方案都没有编译结果（正在部署）
        try e.write("build/default.yaml", "schema_list:\n  - schema: py\n")
        #expect(throws: PreviewError.noSchemas) { try PreviewWorkspace.schemas(in: e.rime) }
        // 文件坏了
        try e.write("build/default.yaml", "schema_list: [\n")
        #expect(throws: PreviewError.noSchemas) { try PreviewWorkspace.schemas(in: e.rime) }
    }

    @Test func 应用后的样子() throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("my.custom.yaml", "patch: {}\n")          // 应用不管的配置文件
        try e.write("user.yaml", "x")
        try e.write("rime_ice.userdb/LOG", "x")
        let packages = try GenFixtures.makePackages(in: e.dir.url.appending(path: "cache"))
        let compiler = WritingCompiler(schemas: [(id: "py", name: "测试拼音")])
        let copy = try e.workspace(compiler).preparePending(try GenFixtures.input(Settings(schemas: ["py"]), packages: packages))
        defer { copy.remove() }
        #expect(compiler.compiled == [copy.userDir])
        #expect(copy.root.path.hasPrefix(e.paths.staging.path) && copy.userDir.path.hasPrefix(copy.root.path))
        #expect(exists(copy.userDir, "py.schema.yaml") && exists(copy.userDir, "default.custom.yaml"))
        #expect(exists(copy.userDir, "my.custom.yaml"))
        #expect(!exists(copy.userDir, "user.yaml") && !exists(copy.userDir, "rime_ice.userdb"))
        #expect(copy.schemas == [PreviewSchema(id: "py", name: "测试拼音")])
        // 没碰真实的 Rime 目录
        #expect(!exists(e.rime, "py.schema.yaml") && !exists(e.rime, "build"))
    }

    @Test func 应用后的样子编译失败() throws {
        let e = try env(); defer { e.dir.remove() }
        let packages = try GenFixtures.makePackages(in: e.dir.url.appending(path: "cache"))
        let line = "E20261015 14:07:26.214222 0x1 dict_compiler.cc:86] neither wb.dict.yaml nor wb.dict.yaml found"
        let compiler = WritingCompiler(schemas: [], report: CompileReport(succeeded: false, errors: [line]))
        let input = try GenFixtures.input(Settings(schemas: ["py"]), packages: packages)
        #expect(throws: PreviewError.compileFailed(RimeLog.explain([line]))) { try e.workspace(compiler).preparePending(input) }
        #expect(e.stagingIsEmpty())
    }

    @Test func 应用后的样子没有方案时清理干净() throws {
        let e = try env(); defer { e.dir.remove() }
        let packages = try GenFixtures.makePackages(in: e.dir.url.appending(path: "cache"))
        let input = try GenFixtures.input(Settings(schemas: ["py"]), packages: packages)
        #expect(throws: PreviewError.noSchemas) { try e.workspace().preparePending(input) }   // FakeCompiler 不写 build/
        #expect(e.stagingIsEmpty())
    }
}
