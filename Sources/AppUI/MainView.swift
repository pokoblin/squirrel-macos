import AppCore
import RimeKit
import SwiftUI

/// 主窗口：左边栏 6 页；底部是「应用改动」栏；消息和外部改动用弹窗
struct MainView: View {
    @Bindable var model: MainModel

    var body: some View {
        NavigationSplitView {
            List(MainModel.Page.allCases, selection: Binding(get: { model.page }, set: { if let page = $0 { model.page = page } })) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    page
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(model.working != nil)
                ApplyBar(model: model)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .alert(model.notice?.title ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
               presenting: model.notice) { notice in
            if let action = notice.action, let title = notice.actionTitle {
                Button(title) { Task { await model.perform(action) } }
            }
            Button("好", role: .cancel) {}
        } message: { notice in
            Text(notice.lines.joined(separator: "\n"))
        }
        .confirmationDialog("有文件在应用外被改过", isPresented: Binding(get: { model.pendingExternalChanges != nil }, set: { _ in }),
                            titleVisibility: .visible) {
            Button("覆盖（先备份）") { Task { await model.resolveExternalChanges(.overwrite) } }
            if model.pendingPersonalChanges {
                Button("采用外面改过的个人词库，其余覆盖") { Task { await model.resolveExternalChanges(.adoptPersonal) } }
            }
            Button("放弃这次改动", role: .cancel) { Task { await model.resolveExternalChanges(.cancel) } }
        } message: {
            Text((model.pendingExternalChanges ?? []).map(\.description).joined(separator: "\n"))
        }
    }

    @ViewBuilder var page: some View {
        switch model.page {
        case .schemas: Text(model.page.title)
        case .appearance: Text(model.page.title)
        case .textReplacement: Text(model.page.title)
        case .transfer: Text(model.page.title)
        case .backups: Text(model.page.title)
        case .diagnostics: Text(model.page.title)
        }
    }
}

/// 底部：正在做什么，或者「有改动还没应用 [撤销] [应用改动]」
struct ApplyBar: View {
    let model: MainModel

    var body: some View {
        if let working = model.working {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(working)
                Spacer()
            }
            .padding(12)
            .background(.bar)
        } else if model.isDirty {
            HStack(spacing: 10) {
                Label("有改动还没应用", systemImage: "pencil.circle")
                Spacer()
                Button("撤销") { model.revert() }
                Button("应用改动") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
    }
}
