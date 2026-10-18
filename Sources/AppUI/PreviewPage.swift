import AppCore
import RimeKit
import SwiftUI

/// 「试打」页：在配置的副本上用 librime 打几个字，看候选长什么样（不碰真实配置，也不用切输入法）
struct PreviewPage: View {
    let model: MainModel
    @FocusState private var inputFocused: Bool

    private var preview: PreviewModel { model.preview }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("试打和置顶").font(.title2.bold())
            // 候选窗口由鼠须管自己画，外观设置不经过 librime，这里看不出来
            Text("这里看的是候选内容（出哪些字词、什么顺序）。字体、颜色、横排竖排这些外观，要在真的用鼠须管打字时看。")
                .font(.callout).foregroundStyle(.secondary)
            controls
            if preview.needsReload(draft: model.draft) || (preview.source == .pending && !model.hasPendingChanges) {
                reloadHint
            }
            ForEach(Array(preview.notes.enumerated()), id: \.offset) { _, note in
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            switch preview.phase {
            case .idle:
                EmptyView()
            case let .preparing(text):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(text)
                }
            case .ready:
                inputArea
                committedArea
                if let version = preview.librimeVersion {
                    Text("librime \(version)（鼠须管自带的）").font(.caption).foregroundStyle(.secondary)
                }
            case let .failed(problem):
                failure(problem)
            }
            if let message = model.pins.message {
                Label(message, systemImage: "pin").font(.callout)
            }
            // 不放进 .ready：准备中、出错（比如没装鼠须管）时也能看、能还原
            PinListSection(model: model)
        }
        .task { await preview.enter(draft: model.draft, hasPending: model.hasPendingChanges) }
        .onDisappear { Task { await preview.leave() } }
        .onChange(of: preview.phase) { _, phase in
            if phase == .ready { inputFocused = true }
        }
    }

    // MARK: 顶部：来源和方案

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("来源", selection: Binding(
                get: { preview.source },
                set: { new in
                    // 模型不会接受的请求直接忽略，分段控件才不会和实际来源不一致
                    guard PreviewModel.canSwitch(to: new, hasPending: model.hasPendingChanges) else { return }
                    Task { await preview.switchSource(new, draft: model.draft, hasPending: model.hasPendingChanges) }
                }
            )) {
                Text("当前生效").tag(PreviewModel.Source.current)
                Text("应用后的样子").tag(PreviewModel.Source.pending)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            // 分段控件里单个选项的 .disabled 在 macOS 上不生效，所以没有改动时整个锁住
            .disabled(!preview.sourcePickerEnabled(hasPending: model.hasPendingChanges))
            .help(model.hasPendingChanges ? "" : "没有未应用的改动")

            if !preview.sourcePickerEnabled(hasPending: model.hasPendingChanges) {
                Text("没有未应用的改动").font(.caption).foregroundStyle(.secondary)
            }

            if !preview.schemas.isEmpty {
                Picker("方案", selection: Binding(
                    get: { preview.schema ?? "" },
                    set: { new in
                        Task {
                            await preview.selectSchema(new)
                            inputFocused = true
                        }
                    }
                )) {
                    ForEach(preview.schemas) { schema in
                        Text(schema.name).tag(schema.id)
                    }
                }
                .fixedSize()
                .disabled(!preview.canSelectSchema)
            }
            Spacer()
        }
    }

    private var reloadHint: some View {
        HStack(spacing: 10) {
            Label("配置变了", systemImage: "arrow.triangle.2.circlepath")
            Button("重新载入") {
                Task { await preview.reload(draft: model.draft, hasPending: model.hasPendingChanges) }
            }
            Spacer()
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 输入区

    private var inputArea: some View {
        let state = preview.state
        return VStack(alignment: .leading, spacing: 8) {
            Text(state.preedit.isEmpty ? "点这里，直接打字（Esc 清空，空格选词）" : state.preedit)
                .font(.title3)
                .foregroundStyle(state.preedit.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 有编码就显示「清空」（没有候选时也能清掉打错的编码）；翻页只在有候选时显示
            if !state.preedit.isEmpty || !state.candidates.isEmpty {
                Divider()
                if !state.candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.candidates.enumerated()), id: \.offset) { index, candidate in
                            HStack(spacing: 4) {
                                Button {
                                    preview.submit(.choose(index))
                                    inputFocused = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("\(label(index, state)).").foregroundStyle(.secondary)
                                        Text(candidate.text)
                                        if !candidate.comment.isEmpty {
                                            Text(candidate.comment).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                                    .background(index == state.highlighted ? Color.accentColor.opacity(0.25) : .clear,
                                                in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                                pinButton(index)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    if !state.candidates.isEmpty {
                        Button("上一页") { preview.submit(.pageUp); inputFocused = true }
                            .disabled(state.pageNo == 0)
                        Button("下一页") { preview.submit(.pageDown); inputFocused = true }
                            .disabled(state.isLastPage)
                        Text("第 \(state.pageNo + 1) 页").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清空") { preview.submit(.clearInput); inputFocused = true }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(inputFocused ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: inputFocused ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($inputFocused)
        .onKeyPress(phases: .down) { press in
            let commandLike = !press.modifiers.isDisjoint(with: [.command, .control, .option])
            let translated = PreviewKeyPress.translate(characters: press.characters, special: Self.specialKey(press.key),
                                                       commandLike: commandLike)
            if translated == .ignored { return .ignored }
            // 排进模型的队列，按键顺序不会乱
            preview.submit(.press(translated))
            return .handled
        }
        .onAppear { inputFocused = true }
    }

    /// 候选旁边的图钉：把它调到这个编码的第一位（不能置顶时灰掉，悬停看原因）
    private func pinButton(_ index: Int) -> some View {
        let availability = preview.pinAvailability(at: index, pinned: model.pins.phrases)
        let reason: String? = if case let .unavailable(why) = availability { why } else { nil }
        return Button {
            Task { await model.pinCandidate(at: index) }
            inputFocused = true
        } label: {
            Image(systemName: "pin")
        }
        .buttonStyle(.borderless)
        .disabled(reason != nil)
        .help(reason ?? "调到第一位")
    }

    private func label(_ index: Int, _ state: PreviewState) -> String {
        if let labels = state.labels, index < labels.count { return labels[index] }
        return "\(index + 1)"
    }

    private static func specialKey(_ key: KeyEquivalent) -> PreviewKey? {
        switch key {
        case .delete: return .backspace
        case .escape: return .escape
        case .return: return .return
        case KeyEquivalent("\u{3}"): return .return   // 小键盘的回车（Enter）
        case .pageUp: return .pageUp
        case .pageDown: return .pageDown
        case .upArrow: return .up
        case .downArrow: return .down
        default: return nil
        }
    }

    // MARK: 已上屏

    private var committedArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已上屏").font(.headline)
                Spacer()
                Button("清空") { preview.clearCommitted(); inputFocused = true }
                    .controlSize(.small)
                    .disabled(preview.committedText.isEmpty)
            }
            Text(preview.committedText.isEmpty ? "选了词的文字会出现在这里" : preview.committedText)
                .foregroundStyle(preview.committedText.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: 出错

    private func failure(_ problem: PreviewProblem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(problem.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(Array(problem.lines.enumerated()), id: \.offset) { _, line in
                Text(line).textSelection(.enabled)
            }
            HStack {
                if problem == PreviewProblem.notInstalled {
                    Button("去诊断页") { model.page = .diagnostics }
                }
                if problem.canRetry {
                    Button("重试") {
                        Task { await preview.retry(draft: model.draft, hasPending: model.hasPendingChanges) }
                    }
                }
            }
        }
    }
}
