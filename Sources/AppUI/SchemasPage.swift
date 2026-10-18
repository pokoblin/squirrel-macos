import AppCore
import RimeKit
import SwiftUI

struct SchemasPage: View {
    @Bindable var model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("启用的方案").font(.title2.bold())
            Text("第一个是默认方案；拖动可以调整顺序。按 Control+0（或 F4）可以在方案之间切换。")
                .foregroundStyle(.secondary)
            List {
                ForEach(model.draft.schemas, id: \.self) { id in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Text(model.schemaName(id))
                        if id == model.draft.schemas.first {
                            Text("默认").font(.caption).padding(.horizontal, 6).background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Button { model.setEnabled(id, false) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("不启用这个方案")
                    }
                }
                .onMove { model.moveSchemas(from: $0, to: $1) }
            }
            .listStyle(.bordered)
            .frame(height: CGFloat(model.draft.schemas.count) * 30 + 12)
            if let note = model.mixedPackagesNote { Note(text: note) }

            HStack(alignment: .firstTextBaseline) {
                Text("可以启用的方案").font(.title2.bold())
                Spacer()
                Button("检查更新") { Task { await model.checkUpdates() } }
                    .disabled(model.working != nil)
            }
            Text(NetworkUse.catalogCheckNote).font(.caption).foregroundStyle(.secondary)
            ForEach(model.catalogPackages, id: \.id) { package in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(package.summary).font(.caption).foregroundStyle(.secondary)
                        ForEach(package.schemas, id: \.id) { schema in
                            Toggle(schema.name, isOn: Binding(get: { model.isEnabled(schema.id) },
                                                              set: { model.setEnabled(schema.id, $0) }))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("\(package.name)（\(package.license)）").font(.headline)
                }
            }

            if !model.optionPackages.isEmpty {
                Text("选项").font(.title2.bold())
                ForEach(model.optionPackages, id: \.id) { package in
                    ForEach(package.options, id: \.id) { option in
                        Picker("\(package.name) · \(option.name)",
                               selection: Binding(get: { model.choice(option, of: package) },
                                                  set: { model.setChoice($0, option: option, of: package) })) {
                            ForEach(option.choices, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
        }
    }
}
