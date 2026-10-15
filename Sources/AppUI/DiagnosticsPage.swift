import AppCore
import RimeKit
import SwiftUI

struct DiagnosticsPage: View {
    let model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("诊断").font(.title2.bold())
                Spacer()
                Button("重新检查") { Task { await model.runDiagnostics() } }
            }
            ForEach(Array(model.checks.enumerated()), id: \.offset) { _, check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(check.level))
                        .foregroundStyle(color(check.level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(check.name)：\(check.message)")
                        if let hint = check.hint {
                            Text(hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Divider().padding(.vertical, 6)
            Text("应用什么时候会联网").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("什么时候").bold()
                    Text("连哪里").bold()
                    Text("下载什么").bold()
                }
                ForEach(NetworkUse.rows, id: \.when) { row in
                    GridRow {
                        Text(row.when)
                        Text(row.host)
                        Text(row.what)
                    }
                }
            }
            .font(.callout)
            Text(NetworkUse.footer).font(.caption).foregroundStyle(.secondary)
            Text(NetworkUse.catalogSource(model.catalogStatus)).font(.caption).foregroundStyle(.secondary)
            if let problem = model.catalogStatus.cacheProblem {
                Text("在线方案清单的缓存用不了：\(problem)。先用内置的").font(.caption).foregroundStyle(.orange)
            }
        }
        .task { await model.runDiagnostics() }
    }

    func symbol(_ level: CheckLevel) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    func color(_ level: CheckLevel) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .orange
        case .problem: return .red
        }
    }
}
