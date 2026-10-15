import Foundation
import Testing
@testable import RimeKit

@Suite struct TextReplacementSyncTests {
    let a = Phrase(text: "替换甲", code: "tha", weight: 1)
    let b = Phrase(text: "替换乙", code: "thb", weight: 1)
    let c = Phrase(text: "替换丙", code: "thc", weight: 1)

    @Test func 每条哈希不看权重和顺序_重复的只算一条() {
        let heavier = Phrase(text: a.text, code: a.code, weight: 9)
        #expect(TextReplacementSync.entryHashes([a, b]) == TextReplacementSync.entryHashes([b, heavier, a]))
        #expect(TextReplacementSync.entryHashes([a, b]).count == 2)
        #expect(TextReplacementSync.hash([a, b]) == TextReplacementSync.hash([b, a]))
        #expect(TextReplacementSync.hash([a]) != TextReplacementSync.hash([a, b]))
    }

    @Test func 哈希里看不出内容() {
        let joined = TextReplacementSync.entryHashes([a]).joined() + TextReplacementSync.hash([a])
        #expect(!joined.contains("替换甲"))
        #expect(!joined.contains("tha"))
    }

    @Test func 数出新增和删掉的条数() {
        var s = Settings(schemas: ["py"])
        s.textReplacement.sync = true
        let synced = s.recordingTextReplacement([a, b]).textReplacement
        #expect(TextReplacementSync.changes([a, b], since: synced) == .init(added: 0, removed: 0))
        #expect(TextReplacementSync.changes([a, b], since: synced)?.isEmpty == true)
        #expect(TextReplacementSync.changes([a, b, c], since: synced) == .init(added: 1, removed: 0))
        #expect(TextReplacementSync.changes([a], since: synced) == .init(added: 0, removed: 1))
        // 改了内容：一删一增
        let edited = Phrase(text: "替换乙改", code: b.code, weight: 1)
        #expect(TextReplacementSync.changes([a, edited], since: synced) == .init(added: 1, removed: 1))
    }

    @Test func 从没同步过时没有变化可比() {
        #expect(TextReplacementSync.changes([a], since: TextReplacementSettings(sync: true)) == nil)
    }

    @Test func 同步关着时清掉记录() {
        var s = Settings(schemas: ["py"])
        s.textReplacement.sync = true
        var recorded = s.recordingTextReplacement([a])
        #expect(recorded.textReplacement.syncedEntries == TextReplacementSync.entryHashes([a]))
        #expect(recorded.textReplacement.lastSyncedHash == TextReplacementSync.hash([a]))
        recorded.textReplacement.sync = false
        let off = recorded.recordingTextReplacement([a])
        #expect(off.textReplacement == TextReplacementSettings(sync: false))
    }

    @Test func 导出用的设置去掉记录() {
        var s = Settings(schemas: ["py"])
        s.textReplacement.sync = true
        let stripped = s.recordingTextReplacement([a]).withoutTextReplacementRecord
        #expect(stripped.textReplacement == TextReplacementSettings(sync: true))
    }

    @Test func 旧的设置文件没有每条哈希也能读() throws {
        let json = #"{"formatVersion":1,"schemas":["py"],"options":{},"appearance":{},"textReplacement":{"sync":true,"lastSyncedHash":"x"},"preservedPatches":{}}"#
        let s = try JSONCoding.decoder.decode(Settings.self, from: Data(json.utf8))
        #expect(s.textReplacement == TextReplacementSettings(sync: true, lastSyncedHash: "x"))
        #expect(s.textReplacement.syncedEntries == nil)
    }
}
