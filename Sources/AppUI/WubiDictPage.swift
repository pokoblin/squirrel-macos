import AppCore
import RimeKit
import SwiftUI

/// 「五笔词库」页：加词、看和改个人词库、检查能不能打出来、批量导入（设计 4.1）。
/// 词库的改动马上写进应用自己的 personal 里，「应用改动」时才进鼠须管的目录
struct WubiDictPage: View {
    @Bindable var model: MainModel
    @State private var importing = false
    @State private var editing: EditTarget?

    private var wubi: WubiDictModel { model.wubiDict }
    private var busy: Bool { wubi.isSaving || wubi.isLoading || wubi.isChecking }

    /// 点「改」时看到的词条：模型核对第 index 个还是它，不是就不改
    struct EditTarget: Identifiable {
        var id: Int
        var entry: DictEntry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("五笔词库").font(.title2.bold())
            Text("这里管极点五笔的个人词库：自己加的词、改过的编码和位置。改动先存在应用里，点「应用改动」后鼠须管才会用上。")
                .font(.callout).foregroundStyle(.secondary)
            messageLine
            content
        }
        .task { await wubi.load(settings: model.draft) }
        .sheet(isPresented: $importing) { WubiImportSheet(wubi: wubi) }
        .sheet(item: $editing) { target in
            WubiEditSheet(wubi: wubi, index: target.id, entry: target.entry)
        }
    }

    // MARK: 提示

    @ViewBuilder private var messageLine: some View {
        if let message = wubi.message {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(message, systemImage: "info.circle")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { wubi.message = nil } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .help("不再显示这条")
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: 内容

    @ViewBuilder private var content: some View {
        if !wubi.availability.canEdit {
            unavailable
        } else {
            if wubi.availability == .badDict, let text = wubi.availability.message {
                Note(text: text)
            }
            if wubi.externallyChanged { externalNotice }
            AddWordSection(wubi: wubi, busy: busy)
            Divider()
            listSection
        }
    }

    @ViewBuilder private var unavailable: some View {
        if wubi.isLoading || !wubi.isLoaded {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在读五笔词库……")
            }
        } else if let text = wubi.availability.message {
            Note(text: text)
            if wubi.availability == .notEnabled {
                Button("去「方案」页") { model.page = .schemas }
            }
        }
    }

    private var externalNotice: some View {
        HStack(spacing: 10) {
            Label("鼠须管目录里的五笔个人词库在应用外被改过", systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("把外面加的词收进来") { Task { _ = await wubi.mergeExternal() } }
                .disabled(busy)
        }
        .padding(8)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 列表

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("个人词库（\(wubi.entries.count) 个词）").font(.headline)
                Spacer()
                Button("从文本导入……") { importing = true }
                    .disabled(busy)
                Button("检查能不能打出来") { Task { await wubi.check(draft: model.draft) } }
                    .disabled(busy || wubi.entries.isEmpty)
            }
            if wubi.isChecking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在试打每个词，稍等一下……").font(.caption).foregroundStyle(.secondary)
                }
            } else if !wubi.checkResults.isEmpty {
                Text("检查用的是「应用后的样子」。词库一改，检查结果就清掉。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("搜索词或编码", text: Bindable(wubi).searchText)
                .textFieldStyle(.roundedBorder)
            if wubi.entries.isEmpty {
                Text("个人词库里还没有词。").foregroundStyle(.secondary)
            } else {
                let rows = wubi.visibleIndices
                if rows.isEmpty {
                    Text("没有找到。").foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(rows, id: \.self) { i in
                            entryRow(i)
                        }
                    }
                    .listStyle(.bordered)
                    .frame(height: 320)
                }
            }
        }
    }

    private func entryRow(_ i: Int) -> some View {
        HStack(spacing: 12) {
            Text(wubi.entries[i].text).frame(minWidth: 90, alignment: .leading)
            Text(wubi.codes[i] ?? "算不出")
                .font(.body.monospaced())
                .foregroundStyle(wubi.codes[i] == nil ? .red : .primary)
                .frame(width: 60, alignment: .leading)
            Text(wubi.positions[i].map { "第 \($0) 个" } ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            checkText(wubi.checkResults[i])
            Spacer()
            Menu {
                rowActions(i)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(busy)
        }
        .contextMenu { rowActions(i) }
    }

    @ViewBuilder private func rowActions(_ i: Int) -> some View {
        // 点的时候就记下这一行的词条：保存、删除时模型核对第 i 个还是它，防止这期间词库变了改错行
        let entry = wubi.entries[i]
        Button("改编码和位置……") { editing = EditTarget(id: i, entry: entry) }
            .disabled(busy)
        Button("删除", role: .destructive) { Task { await wubi.remove(at: i, expected: entry) } }
            .disabled(busy)
    }

    @ViewBuilder private func checkText(_ result: CheckResult?) -> some View {
        switch result {
        case .asExpected(let page, let index):
            Text("第 \(page + 1) 页第 \(index + 1) 个").foregroundStyle(.green)
        case .elsewhere(let page, let index):
            Text("位置和选的不一样：第 \(page + 1) 页第 \(index + 1) 个").foregroundStyle(.orange)
        case .missing:
            Text("打不出来").foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }
}

/// 位置选项的文字：第 n 个就是排在这个词前面；最后一个是「最后」
func wubiPositionLabel(_ n: Int, words: [IndexedWord]) -> String {
    guard n >= 1, n <= words.count else { return "最后" }
    let word = words[n - 1]
    return "第 \(n) 个（在「\(word.text)」\(word.isPersonal ? "（我的）" : "")前面）"
}

// MARK: 加一个词

private struct AddWordSection: View {
    @Bindable var wubi: WubiDictModel
    let busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("加一个词").font(.headline)
            HStack {
                TextField("要加的词", text: $wubi.draftText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit { if wubi.canAdd { Task { await wubi.add() } } }
                Button("加入") { Task { await wubi.add() } }
                    .disabled(!wubi.canAdd || busy)
            }
            if !wubi.draftText.trimmingCharacters(in: .whitespaces).isEmpty {
                codeRow
                positionRow
            }
            if let problem = wubi.draftProblem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var codeRow: some View {
        HStack(spacing: 8) {
            Text("编码")
            TextField("a–y 的 1 到 4 个字母", text: $wubi.draftCode)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 140)
            if wubi.draftCodeChoices.count > 1 {
                Menu("这个词有 \(wubi.draftCodeChoices.count) 种编码") {
                    ForEach(wubi.draftCodeChoices, id: \.self) { code in
                        Button(code) { wubi.draftCode = code }
                    }
                }
                .fixedSize()
            } else if case .codes = wubi.draftEncoding {
                Text("自动算出的，可以改").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("要自己填").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var positionRow: some View {
        if !wubi.draftCode.isEmpty, WubiEncoder.isValidCode(wubi.draftCode) {
            VStack(alignment: .leading, spacing: 6) {
                Text("这个编码现在出什么").font(.subheadline)
                if wubi.existing.isEmpty {
                    Text("还没有词").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(existingText)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("新词排在", selection: $wubi.draftPosition) {
                    ForEach(Array(wubi.draftPositions), id: \.self) { n in
                        Text(wubiPositionLabel(n, words: wubi.existing)).tag(n)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var existingText: String {
        wubi.existing.enumerated()
            .map { "\($0.offset + 1) \($0.element.text)\($0.element.isPersonal ? "（我的）" : "")" }
            .joined(separator: "　")
    }
}

// MARK: 改编码和位置

private struct WubiEditSheet: View {
    let wubi: WubiDictModel
    let index: Int
    /// 打开时看到的词条
    let entry: DictEntry
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?
    @State private var saving = false
    @State private var code = ""
    @State private var position = 1
    @State private var loaded = false
    /// 打开时的编码和位置：编码改回原样，位置也回到原样
    @State private var initialCode = ""
    @State private var initialPosition = 1

    /// 这个编码下除了它自己的词（位置是相对这些词说的）
    private var others: [IndexedWord] {
        var words = wubi.words(for: code)
        if let at = words.firstIndex(where: { $0.isPersonal && $0.text == entry.text }) {
            words.remove(at: at)
        }
        return words
    }

    private var valid: Bool { WubiEncoder.isValidCode(code) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("改「\(entry.text)」的编码和位置").font(.title3.bold())
            HStack {
                Text("编码")
                TextField("a–y 的 1 到 4 个字母", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 140)
            }
            if valid {
                let words = others
                Picker("排在", selection: $position) {
                    ForEach(1...(words.count + 1), id: \.self) { n in
                        Text(wubiPositionLabel(n, words: words)).tag(n)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            } else {
                Text("编码只能是 a 到 y 的小写字母，1 到 4 个").font(.caption).foregroundStyle(.red)
            }
            // 放不进去、已经有了这类问题留在这里，让用户换个位置或编码再存
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    wubi.message = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid || saving || wubi.isSaving || wubi.isLoading)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            guard !loaded, index < wubi.codes.count else { return }
            loaded = true
            code = wubi.codes[index] ?? ""
            initialCode = code
            initialPosition = wubi.positions[index] ?? (others.count + 1)
            position = initialPosition
        }
        .onChange(of: position) { problem = nil }
        // 换了编码：位置回到「最后」（原来的位置只对原来的编码有意义）；改回原来的编码就回到原来的位置
        .onChange(of: code) { _, new in
            guard loaded else { return }
            problem = nil
            position = new == initialCode ? initialPosition : (valid ? others.count : 0) + 1
        }
    }

    private func save() async {
        // 编码和位置都没动：直接关，什么都不写
        if code == initialCode, position == initialPosition {
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        if await wubi.update(at: index, expected: entry, code: code, position: position) {
            dismiss()
        } else {
            problem = wubi.message ?? "没能保存"
            wubi.message = nil
        }
    }
}
