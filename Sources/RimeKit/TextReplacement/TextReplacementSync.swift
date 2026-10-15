import Foundation

/// 文本替换同步的记录（设计 6.5）：只存哈希，不存内容
public enum TextReplacementSync {
    public struct Changes: Sendable, Equatable {
        public let added: Int
        public let removed: Int

        public init(added: Int, removed: Int) {
            self.added = added
            self.removed = removed
        }

        public var isEmpty: Bool { added == 0 && removed == 0 }
    }

    /// 每一条的哈希（短语<Tab>编码，不看权重），去重、排序
    public static func entryHashes(_ phrases: [Phrase]) -> [String] {
        Array(Set(phrases.map { Hashing.sha256(of: Data(($0.text + "\t" + $0.code).utf8)) })).sorted()
    }

    /// 整体的哈希
    public static func hash(_ phrases: [Phrase]) -> String {
        Hashing.sha256(of: Data(entryHashes(phrases).joined(separator: "\n").utf8))
    }

    /// 现在的文本替换和上次同步时比：新增几条、删掉几条（改了内容算一删一增）。从没同步过时为 nil
    public static func changes(_ current: [Phrase], since settings: TextReplacementSettings) -> Changes? {
        guard let synced = settings.syncedEntries else { return nil }
        let now = Set(entryHashes(current))
        let before = Set(synced)
        return Changes(added: now.subtracting(before).count, removed: before.subtracting(now).count)
    }
}

extension Settings {
    /// 同步开着时，记下这次写入用的文本替换（只存哈希）；关着时清掉记录
    public func recordingTextReplacement(_ phrases: [Phrase]) -> Settings {
        var copy = self
        if textReplacement.sync {
            copy.textReplacement.lastSyncedHash = TextReplacementSync.hash(phrases)
            copy.textReplacement.syncedEntries = TextReplacementSync.entryHashes(phrases)
        } else {
            copy.textReplacement.lastSyncedHash = nil
            copy.textReplacement.syncedEntries = nil
        }
        return copy
    }

    /// 去掉同步记录：哈希也是从文本替换内容算出来的，导出文件里不放
    public var withoutTextReplacementRecord: Settings {
        var copy = self
        copy.textReplacement.lastSyncedHash = nil
        copy.textReplacement.syncedEntries = nil
        return copy
    }
}
