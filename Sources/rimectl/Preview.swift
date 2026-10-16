import Foundation
import RimeKit

extension Rimectl {
    struct PreviewOptions {
        var pending: Bool
        var list: Bool
        var schema: String?
        var find: String?
    }

    /// 试打（设计 3.7）：在副本上跑 librime，不碰真实的 Rime 目录
    static func preview(_ codes: [String], options: PreviewOptions, paths: AppPaths, locations: RimeLocations,
                        _ context: Context) async -> Int32 {
        let out = context.output
        // 先查参数，别白白准备副本
        if !options.list {
            guard options.schema != nil, !codes.isEmpty, options.find == nil || codes.count == 1 else {
                out.error(usage)
                return 2
            }
        }
        var copy: PreviewCopy?
        defer { copy?.remove() }
        do {
            let workspace = PreviewWorkspace(paths: paths, locations: locations,
                                             compiler: context.compiler ?? DeployerCompiler(locations: locations))
            if options.pending {
                // 只用已保存的设置和本地缓存的方案包，不联网
                guard let input = try await prepareInput(cacheOnly: true, paths: paths, context) else { return 1 }
                copy = try workspace.preparePending(input)
            } else {
                copy = try workspace.prepareCurrent()
            }
            guard let copy else { return 1 }
            if options.list {
                for schema in copy.schemas { out.line("\(schema.id)\t\(schema.name)") }
                return 0
            }
            guard let schema = options.schema else { return 2 }
            guard copy.schemas.contains(where: { $0.id == schema }) else {
                out.error("没有方案「\(schema)」。可以试打的方案：" + copy.schemas.map(\.id).joined(separator: "、"))
                return 1
            }
            guard let helper = context.previewHelper ?? PreviewHelperLocator.locate() else {
                out.error(PreviewError.helperMissing.description)
                return 1
            }
            // 和应用一样用 locations 里的鼠须管（辅助程序自己默认的是 /Library/Input Methods 里那个）
            let session = PreviewSession(helper: helper, squirrelApp: locations.squirrelApp)
            do {
                _ = try await session.open(userDir: copy.userDir, schema: schema)
                let code = try await run(codes, schema: schema, options: options, session: session, out)
                await session.close()
                return code
            } catch {
                await session.close()
                throw error
            }
        } catch let error as PreviewError {
            out.error(error.description)
            return 1
        } catch {
            out.error(String(describing: error))
            return 1
        }
    }

    private static func run(_ codes: [String], schema: String, options: PreviewOptions, session: PreviewSession,
                            _ out: Output) async throws -> Int32 {
        if let word = options.find {
            let maxPages = 5
            guard let match = try await PreviewProbe.find(word, code: codes[0], maxPages: maxPages, in: session) else {
                out.line("没找到（最多翻了 \(maxPages) 页）")
                return 1
            }
            out.line(match.autoCommitted ? "自动上屏" : "找到：第 \(match.page + 1) 页第 \(match.index + 1) 个")
            return 0
        }
        for code in codes {
            _ = try await session.clear()
            let state = try await session.input(code)
            var line = code + "\t"
            if let committed = state.committed { line += "[上屏]\(committed) " }
            line += state.candidates.map(\.text).joined(separator: " | ")
            out.line(line)
        }
        return 0
    }
}
