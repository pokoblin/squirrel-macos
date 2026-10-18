import AppCore
import RimeKit
import SwiftUI

/// 「试打和置顶」页下面的置顶列表：personal/phrases.txt 里的每一条，都能还原（候选置顶设计 5.4 第 4 条）
struct PinListSection: View {
    let model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("置顶").font(.headline)
            Text("置顶对所有启用的方案都生效。改了以后点「应用改动」才生效。")
                .font(.caption).foregroundStyle(.secondary)
            if let problem = model.pins.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if model.pins.phrases.isEmpty {
                Text("还没有置顶。在上面打编码，点候选旁边的图钉，就能把它调到第一位。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.pins.phrases.enumerated()), id: \.offset) { _, phrase in
                    HStack(spacing: 8) {
                        Text(phrase.code).font(.body.monospaced())
                        Text("→").foregroundStyle(.secondary)
                        Text(phrase.text)
                        Spacer()
                        Button("还原") { model.unpin(phrase) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}
