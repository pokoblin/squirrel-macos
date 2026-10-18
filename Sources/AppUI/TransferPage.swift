import AppCore
import AppKit
import RimeKit
import SwiftUI
import UniformTypeIdentifiers

struct TransferPage: View {
    @Bindable var model: MainModel
    @State private var choosing = false
    @State private var importing: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出").font(.title2.bold())
            Text("把设置、个人词库、手动短语打成一个文件，在新电脑上用这个应用一键导入。不放上游方案文件（导入时下载最新版），也不放文本替换生成的短语。")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("带上输入习惯（导出时输入法会暂停几秒）", isOn: $model.includeUserDB)
            Button("导出…") { chooseExportFile() }
                .buttonStyle(.borderedProminent)
            Divider()
            Text("导入").font(.title2.bold())
            Text("用导出文件换掉现在的设置和个人内容（现在的会先另存一份）；输入习惯是合并，不会丢掉这台电脑上已经学到的。")
                .fixedSize(horizontal: false, vertical: true)
            Button("从导出文件导入…") { choosing = true }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { importing = url }
        }
        .confirmationDialog("导入会换掉现在的设置和个人内容", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                            titleVisibility: .visible) {
            Button("导入") {
                if let url = importing { Task { await model.importFile(url) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.importDropsUnappliedEdits ? "现在的设置和个人内容会另存一份。还没应用的改动也会丢掉。" : "现在的设置和个人内容会另存一份。")
        }
    }

    func chooseExportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = ExportFileName.suggested()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.export(to: url) }
    }
}
