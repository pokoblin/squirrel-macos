import AppCore
import RimeKit
import SwiftUI

struct AppearancePage: View {
    @Bindable var model: MainModel

    var body: some View {
        Form {
            Section("配色") {
                schemePicker("浅色模式", selection: $model.draft.appearance.colorScheme)
                schemePicker("深色模式", selection: $model.draft.appearance.colorSchemeDark)
            }
            Section("字号（浅色、深色配色一起改）") {
                OptionalStepper(title: "候选字", value: $model.draft.appearance.fontPoint, range: Settings.fontPointRange, start: 18)
                OptionalStepper(title: "序号", value: $model.draft.appearance.labelFontPoint, range: Settings.fontPointRange, start: 16)
                OptionalStepper(title: "注释", value: $model.draft.appearance.commentFontPoint, range: Settings.fontPointRange, start: 16)
            }
            Section("排列") {
                Picker("候选", selection: $model.draft.appearance.candidateListLayout) {
                    Text("方案默认").tag(CandidateListLayout?.none)
                    Text("横排").tag(CandidateListLayout?.some(.linear))
                    Text("竖排").tag(CandidateListLayout?.some(.stacked))
                }
                Picker("文字方向", selection: $model.draft.appearance.textOrientation) {
                    Text("方案默认").tag(TextOrientation?.none)
                    Text("横排").tag(TextOrientation?.some(.horizontal))
                    Text("竖排").tag(TextOrientation?.some(.vertical))
                }
                OptionalStepper(title: "每页候选数", value: $model.draft.appearance.pageSize, range: Settings.pageSizeRange, start: 5)
            }
        }
        .formStyle(.grouped)
    }

    func schemePicker(_ title: String, selection: Binding<String?>) -> some View {
        let ids = model.colorSchemes.map(\.id)
        return Picker(title, selection: selection) {
            Text("方案默认").tag(String?.none)
            ForEach(model.colorSchemes) { Text($0.name).tag(String?.some($0.id)) }
            if let current = selection.wrappedValue, !ids.contains(current) {
                Text(current).tag(String?.some(current))
            }
        }
    }
}

/// 可以选「方案默认」的数字设置
struct OptionalStepper: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    /// 从「方案默认」改成自定义时的起始值
    let start: Int

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? start) : nil }))
            Spacer()
            if let current = value {
                Stepper("\(current)", value: Binding(get: { current }, set: { value = $0 }), in: range)
                    .fixedSize()
            } else {
                Text("方案默认").foregroundStyle(.secondary)
            }
        }
    }
}
