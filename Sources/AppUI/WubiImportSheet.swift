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
    /// 预览时每一行的编码（行 id → 编码）：没改过编码的「已经有了」「重复」行不让勾
    @State private var originalCodes: [Int: String] = [:]

    /// 现在点「加入」会加几个（和真的加的一致）
    private var count: Int { wubi.importCount(effectiveRows) }

    /// 这一行勾不上：编码不对、词库里已经有了（用户没改编码时包括和前面的行重复）
    private func blocked(_ row: ImportRow) -> Bool {
        if wubi.importProblem(row) != nil { return true }
        let repeated = row.status == .duplicateInBatch && row.code == originalCodes[row.id]
        return repeated
    }

    /// 真正要加的：勾着但勾不上的行不算
    private var effectiveRows: [ImportRow] {
        (rows ?? []).map { row in
            var row = row
            row.selected = row.selected && !blocked(row)
            return row
        }
    }

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
                    let chosen = effectiveRows
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
            Text("共 \(list.count) 行，会加入 \(count) 行。可以改编码、选排在第几，已经有了的词不能勾。")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(Binding($rows) ?? .constant([])) { $row in
                    HStack(spacing: 10) {
                        let isBlocked = blocked(row)
                        Toggle("", isOn: Binding(get: { row.selected && !isBlocked }, set: { row.selected = $0 }))
                            .labelsHidden()
                            // 没有合法编码、词库里已经有了的行勾不上：先改编码
                            .disabled(isBlocked)
                        Text(row.text).frame(width: 110, alignment: .leading).lineLimit(1)
                        codeField($row)
                        positionPicker($row)
                        statusLabel(row)
                        Spacer()
                    }
                    // 换了编码，原来选的位置就没意义了
                    .onChange(of: row.code) { row.position = nil }
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

    /// 排在第几：只有这个编码下已经有词（或者行里写了权重）的行才需要选
    @ViewBuilder private func positionPicker(_ row: Binding<ImportRow>) -> some View {
        let value = row.wrappedValue
        let words = wubi.words(for: value.code)
        if WubiEncoder.isValidCode(value.code), !words.isEmpty || value.weight != nil {
            let last = words.count + 1
            Picker("", selection: Binding(
                get: { value.position.map { min($0, last) } ?? (value.weight != nil ? 0 : last) },
                set: { new in
                    // 0 是「按行里写的权重」；没写权重的行，选「最后」就是没选
                    row.wrappedValue.position = new == 0 || (new == last && value.weight == nil) ? nil : new
                }
            )) {
                if value.weight != nil { Text("按文件里的权重").tag(0) }
                ForEach(1...last, id: \.self) { n in
                    Text(wubiPositionLabel(n, words: words)).tag(n)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            // 位置放不进去时菜单要留着，让用户换一个位置；只有这一行本身加不了才锁
            .disabled(wubi.importProblem(value, ignoringPosition: true) != nil
                      || (value.status == .duplicateInBatch && value.code == originalCodes[value.id]))
        } else {
            Color.clear.frame(width: 170, height: 1)
        }
    }

    /// 状态：没改过编码就是预览时的状态；改过就是现在这样能不能加
    private func statusLabel(_ row: ImportRow) -> some View {
        let changed = row.code != originalCodes[row.id]
        let problem = wubi.importProblem(row)
        let text = changed ? (problem ?? "可以加") : Self.statusText(row.status, problem: problem)
        let color: Color = problem == nil ? (changed ? .secondary : Self.statusColor(row.status)) : .orange
        return Text(text).font(.caption).foregroundStyle(color)
    }

    static func statusText(_ status: ImportStatus, problem: String? = nil) -> String {
        // 位置放不进去这类，状态本身没写，要把原因带出来
        if let problem, status == .ok || status == .choose { return problem }
        return statusText(status)
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
        let parsed = await wubi.importRows(text)
        originalCodes = Dictionary(uniqueKeysWithValues: parsed.map { ($0.id, $0.code) })
        rows = parsed
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
