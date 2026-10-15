import AppCore
import RimeKit
import SwiftUI

struct BackupsPage: View {
    let model: MainModel
    @State private var restoring: BackupInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备份").font(.title2.bold())
            Text("每次写入前都会备份 Rime 目录里的配置文件（留最近 10 份；第一次接管、导入前的那份永久保留）。还原只换回 Rime 目录里的文件，应用里的设置不变；之后再「应用改动」会按应用里的设置重新写入。")
                .fixedSize(horizontal: false, vertical: true)
            if model.backups.isEmpty {
                Text("还没有备份").foregroundStyle(.secondary)
            }
            ForEach(model.backups, id: \.id) { backup in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backup.createdAt.formatted(date: .numeric, time: .shortened))
                        Text("\(backup.reason)\(backup.permanent ? "，永久保留" : "") · \(backup.files.count) 个文件")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("还原…") { restoring = backup }
                }
                Divider()
            }
        }
        .task { model.loadBackups() }
        .confirmationDialog("还原到这个备份？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("还原") {
                if let backup = restoring { Task { await model.restore(backup.id) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("还原前会先给现在的状态做一份备份，还原也能撤销。")
        }
    }
}
