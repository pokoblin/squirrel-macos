import Foundation
import Yams

/// 试打页里可以选的一个方案
public struct PreviewSchema: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 一份用来试打的副本。用完要调用 remove()
public struct PreviewCopy: Sendable, Equatable {
    /// 暂存区里的 preview-<UUID>，整个删掉就是清理
    public var root: URL
    /// 交给辅助程序当用户目录的那个目录（里面有 build/）
    public var userDir: URL
    public var schemas: [PreviewSchema]

    public init(root: URL, userDir: URL, schemas: [PreviewSchema]) {
        self.root = root
        self.userDir = userDir
        self.schemas = schemas
    }

    public func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// 给试打准备副本（设计 3.4）。只读 Rime 目录，不拿应用锁，不联网。
public struct PreviewWorkspace: Sendable {
    let paths: AppPaths
    let locations: RimeLocations
    let compiler: any RimeCompiler

    public init(paths: AppPaths, locations: RimeLocations, compiler: any RimeCompiler) {
        self.paths = paths
        self.locations = locations
        self.compiler = compiler
    }

    /// 「当前生效」：复制 Rime 目录（带 build/，不带输入习惯和 Rime 自己的运行文件）
    public func prepareCurrent() throws -> PreviewCopy {
        let fm = FileManager.default
        // Rime 目录可能是符号链接（放在网盘、dotfiles 里）：要复制它指向的真实内容
        let rime = locations.rimeDirectory.resolvingSymlinksInPath()
        guard fm.fileExists(atPath: rime.appending(path: "build").path) else { throw PreviewError.notDeployed }
        return try makeCopy { root in
            let userDir = root.appending(path: "user", directoryHint: .isDirectory)
            try fm.createDirectory(at: userDir, withIntermediateDirectories: true)
            for name in try fm.contentsOfDirectory(atPath: rime.path).sorted() {
                // build 是要的：里面是鼠须管编译好的结果
                if RimeFiles.isRimeOwned(name), name != "build" { continue }
                // 顶层的符号链接换成真实内容；指向不存在的链接跳过
                try Deployer.copy(rime.appending(path: name), to: userDir.appending(path: name))
            }
            return (userDir, try Self.schemas(in: userDir))
        }
    }

    /// 「应用后的样子」：和点「应用」时一样拼出完整配置并编译，但全程在副本里
    public func preparePending(_ input: GenerationInput) throws -> PreviewCopy {
        try makeCopy { root in
            let generated = root.appending(path: "generated", directoryHint: .isDirectory)
            let full = root.appending(path: "full", directoryHint: .isDirectory)
            let result = try ConfigGenerator().generate(input, into: generated)
            try FullConfig.assemble(rime: locations.rimeDirectory, ledger: try Ledger.load(paths), generated: generated,
                                    newPaths: result.files.map(\.path), into: full)
            let compiled = try compiler.compile(full)
            guard compiled.succeeded else { throw PreviewError.compileFailed(RimeLog.explain(compiled.errors)) }
            return (full, try Self.schemas(in: full))
        }
    }

    /// 编译出来的方案列表：`build/default.yaml` 的 schema_list（已经合并过补丁），
    /// 只留 `build/<id>.schema.yaml` 真的存在的（复制时鼠须管正在部署，可能缺）。名字取 schema/name，没有就用 id。
    public static func schemas(in userDir: URL) throws -> [PreviewSchema] {
        let build = userDir.appending(path: "build", directoryHint: .isDirectory)
        guard let text = try? String(contentsOf: build.appending(path: "default.yaml"), encoding: .utf8),
              let root = (try? Yams.load(yaml: text)) as? [String: Any],
              let list = root["schema_list"] as? [Any] else { throw PreviewError.noSchemas }
        var result: [PreviewSchema] = []
        for item in list {
            guard let id = (item as? [String: Any])?["schema"] as? String,
                  !id.isEmpty, !id.contains("/"), !result.contains(where: { $0.id == id }),
                  let schemaText = try? String(contentsOf: build.appending(path: "\(id).schema.yaml"), encoding: .utf8)
            else { continue }
            let schema = (try? Yams.load(yaml: schemaText)) as? [String: Any]
            let name = ((schema?["schema"] as? [String: Any])?["name"]).map { String(describing: $0) } ?? ""
            result.append(PreviewSchema(id: id, name: name.isEmpty ? id : name))
        }
        guard !result.isEmpty else { throw PreviewError.noSchemas }
        return result
    }

    /// 在暂存区建一个 preview-<UUID>，做完返回副本；任何一步出错都先删掉再抛
    private func makeCopy(_ build: (URL) throws -> (userDir: URL, schemas: [PreviewSchema])) throws -> PreviewCopy {
        let root = paths.staging.appending(path: "preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let made = try build(root)
            return PreviewCopy(root: root, userDir: made.userDir, schemas: made.schemas)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}
