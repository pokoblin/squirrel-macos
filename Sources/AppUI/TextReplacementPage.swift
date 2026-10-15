import AppCore
import RimeKit
import SwiftUI

struct TextReplacementPage: View {
    @Bindable var model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("macOS 文本替换").font(.title2.bold())
            Text("把「系统设置 → 键盘 → 文本替换」里的条目变成鼠须管的自定义短语。快捷码只有英文字母的条目才能在鼠须管里打出来。文本替换的内容不会导出（同一个 Apple 账户在新电脑上会自动同步）。")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("同步文本替换", isOn: $model.draft.textReplacement.sync)
            Text("打开、关掉以后，点底部的「应用改动」才生效。同步开着时，每次应用改动都会带上最新的文本替换。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("现在的状态").font(.headline)
                Spacer()
                Button("检查") { Task { await model.checkTextReplacement() } }
            }
            if let status = model.textReplacementStatus {
                if let error = status.error {
                    Note(text: "读不了文本替换：\(error)")
                } else {
                    Text("能用的 \(status.usable) 条")
                    if status.badShortcut > 0 { Text("快捷码里有英文字母以外的字符、打不出来的 \(status.badShortcut) 条").foregroundStyle(.secondary) }
                    if status.badPhrase > 0 { Text("内容是空的、有换行或 Tab 的 \(status.badPhrase) 条").foregroundStyle(.secondary) }
                    if status.synced {
                        if let changes = status.changes {
                            if changes.isEmpty {
                                Label("和上次同步时一样", systemImage: "checkmark.circle")
                            } else {
                                Note(text: "和上次同步比：新增 \(changes.added) 条，删掉 \(changes.removed) 条")
                                Button("同步这些变化") { Task { await model.syncTextReplacement(); await model.checkTextReplacement() } }
                                    .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Note(text: "还没同步过")
                            Button("现在同步") { Task { await model.syncTextReplacement(); await model.checkTextReplacement() } }
                        }
                    }
                }
            }
        }
        .task { await model.checkTextReplacement() }
    }
}
