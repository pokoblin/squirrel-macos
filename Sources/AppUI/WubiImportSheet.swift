import AppCore
import RimeKit
import SwiftUI
import UniformTypeIdentifiers

/// 「从文本导入……」：粘贴或选文件，先预览每一行，再把勾上的加进个人词库（设计 4.3）
struct WubiImportSheet: View {
    let wubi: WubiDictModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var rows: [ImportRow]?
    @State private var parsing = false
    @State private var choosing = false
    @State private var problem: String?

    /// 勾上的、编码合法的行数
    private var count: Int { WubiImport.entries(from: rows ?? []).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("从文本导入").font(.title3.bold())
            Text("一行一个词：「词」、「词 编码」或「词（Tab）编码（Tab）权重」。空行和 # 开头的行会跳过。只写词时自动算编码，排在已有的字词后面。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(height: rows == nil ? 200 : 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            HStack {
                Button("选文件……") { choosing = true }
                Button("预览") { Task { await preview() } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsing)
                if parsing { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
            if let rows {
                table(rows)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("加入 \(count) 个") {
                    let chosen = rows ?? []
                    dismiss()
                    Task { await wubi.confirmImport(chosen) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0)
            }
        }
        .padding(20)
        .frame(width: 640)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.plainText, .text]) { result in
            load(result)
        }
        // 文字改了，之前的预览就过时了
        .onChange(of: text) { rows = nil }
    }

    // MARK: 表

    @ViewBuilder private func table(_ list: [ImportRow]) -> some View {
        if list.isEmpty {
            Text("没有认出可以导入的行。").foregroundStyle(.secondary)
        } else {
            let selected = list.filter(\.selected).count
            Text("共 \(list.count) 行，勾上了 \(selected) 行。改了编码以后，加入时会再查一次有没有重复。")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(Binding($rows) ?? .constant([])) { $row in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $row.selected)
                            .labelsHidden()
                            // 没有合法编码的行勾不上，先填编码
                            .disabled(!WubiEncoder.isValidCode(row.code))
                        Text(row.text).frame(width: 130, alignment: .leading).lineLimit(1)
                        codeField($row)
                        Text(Self.statusText(row.status))
                            .font(.caption)
                            .foregroundStyle(Self.statusColor(row.status))
                        Spacer()
                    }
                }
            }
            .listStyle(.bordered)
            .frame(height: 260)
        }
    }

    @ViewBuilder private func codeField(_ row: Binding<ImportRow>) -> some View {
        if row.wrappedValue.choices.count > 1 {
            Picker("", selection: row.code) {
                ForEach(row.wrappedValue.choices, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
        } else {
            TextField("编码", text: row.code)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 90)
        }
    }

    static func statusText(_ status: ImportStatus) -> String {
        switch status {
        case .ok: return "可以加"
        case .choose: return "有多个可能的编码，选一个"
        case .needsCode: return "算不出编码或编码不对，请自己填"
        case .alreadyPersonal: return "已经加过了"
        case .alreadyInDict: return "词库里已经有了"
        case .duplicateInBatch: return "和前面的行重复"
        }
    }

    static func statusColor(_ status: ImportStatus) -> Color {
        switch status {
        case .ok, .choose: return .secondary
        case .needsCode: return .red
        case .alreadyPersonal, .alreadyInDict, .duplicateInBatch: return .orange
        }
    }

    // MARK: 动作

    private func preview() async {
        parsing = true
        problem = nil
        defer { parsing = false }
        rows = await wubi.importRows(text)
    }

    private func load(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            problem = "没能打开文件：\(error.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let content = String(data: data, encoding: .utf8) else {
                    problem = "这个文件不是 UTF-8 文本，读不了"
                    return
                }
                problem = nil
                text = content
                Task { await preview() }
            } catch {
                problem = "没能读文件：\(error.localizedDescription)"
            }
        }
    }
}
