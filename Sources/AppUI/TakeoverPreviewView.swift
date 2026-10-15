import AppCore
import SwiftUI

/// 接管预览：认出来的设置、个人内容的条数、接管后会变的文件（只有名字和条数）
struct TakeoverPreviewView: View {
    let summary: TakeoverSummary

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Row(title: "方案（第一个是默认）", items: summary.schemas)
                if !summary.options.isEmpty { Row(title: "选项", items: summary.options) }
                Row(title: "外观", items: summary.appearance.isEmpty ? ["都是方案默认的"] : summary.appearance)
                if !summary.preservedPatches.isEmpty { Row(title: "保留你改过的", items: summary.preservedPatches) }
                Row(title: "个人内容", items: [
                    "个人词库 \(summary.personalDicts.count) 个" + (summary.personalDicts.isEmpty ? "" : "（\(summary.personalDicts.joined(separator: "、"))）"),
                    "手动短语 \(summary.manualPhrases) 条",
                ] + (summary.textReplacementMatches > 0
                    ? ["和 macOS 文本替换一样的短语 \(summary.textReplacementMatches) 条（接管后打开文本替换同步）"] : []))
                ForEach(Array((summary.notes + (summary.blockedReason.map { [$0] } ?? [])).enumerated()), id: \.offset) { _, note in
                    Note(text: note)
                }
                Divider()
                Text("接管后：换掉 \(summary.replaced.count) 个文件，内容不变 \(summary.unchanged) 个，新加 \(summary.added.count) 个，原样保留 \(summary.kept.count) 个")
                    .font(.callout)
                Files(title: "换掉", files: summary.replaced)
                Files(title: "新加", files: summary.added)
                Files(title: "原样保留", files: summary.kept)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct Row: View {
        let title: String
        let items: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct Files: View {
        let title: String
        let files: [String]

        var body: some View {
            if !files.isEmpty {
                DisclosureGroup("\(title)（\(files.count) 个）") {
                    Text(files.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
