import Foundation

/// 某个词在候选里的位置。page、index 都从 0 数起
public struct PreviewMatch: Sendable, Equatable {
    public var page: Int
    public var index: Int
    /// 从第一个候选数起的总位置（前面几页的候选数加上本页的序号，从 0 起）。自动上屏算 0
    public var overall: Int
    /// 输入完编码就直接上屏了（比如五笔四码唯一时自动上屏），没有候选可选
    public var autoCommitted: Bool

    public init(page: Int, index: Int, overall: Int, autoCommitted: Bool) {
        self.page = page
        self.index = index
        self.overall = overall
        self.autoCommitted = autoCommitted
    }
}

/// 在引擎里打一个编码，找某个词排在第几页第几个
public enum PreviewProbe {
    /// 先清空，再输入 code。maxPages 是最多看几页（翻页最多 maxPages - 1 次）。
    /// 没找到（翻到最后一页，或者看满了 maxPages 页）返回 nil
    public static func find(
        _ text: String, code: String, maxPages: Int = 5, in engine: any PreviewEngine
    ) async throws -> PreviewMatch? {
        _ = try await engine.clear()
        var state = try await engine.input(code)
        if state.committed == text {
            return PreviewMatch(page: 0, index: 0, overall: 0, autoCommitted: true)
        }
        var page = 0
        var before = 0
        while true {
            if let index = state.candidates.firstIndex(where: { $0.text == text }) {
                return PreviewMatch(page: page, index: index, overall: before + index, autoCommitted: false)
            }
            if state.isLastPage || page + 1 >= maxPages { return nil }
            before += state.candidates.count
            state = try await engine.key(.pageDown)
            page += 1
        }
    }
}
