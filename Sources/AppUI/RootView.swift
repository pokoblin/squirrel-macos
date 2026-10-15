import AppCore
import RimeKit
import SwiftUI
import UniformTypeIdentifiers

/// 应用的根视图：先走第一次打开的引导，设置好了进主窗口
public struct RootView: View {
    let state: AppState?

    public init(state: AppState?) {
        self.state = state
    }

    public var body: some View {
        if let state {
            if let main = state.main {
                MainView(model: main)
            } else if let error = state.openError {
                Message(symbol: "exclamationmark.triangle", title: "打不开主窗口", lines: [error])
                    .padding(40)
                    .frame(width: 560)
            } else {
                SetupView(flow: state.setup, onFinish: { state.openMain(welcome: $0) })
                    .task { await state.start() }
                    .frame(width: 560)
                    .frame(minHeight: 360)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Message(symbol: "exclamationmark.triangle", title: "应用里找不到方案清单",
                        lines: ["应用好像坏了，请重新下载"])
            }
            .padding(40)
            .frame(width: 560)
        }
    }
}

struct SetupView: View {
    let flow: SetupFlow
    let onFinish: ([String]) -> Void
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                Task { await flow.importFile(url) }
            }
        }
    }

    @ViewBuilder var content: some View {
        switch flow.step {
        case .checking:
            Working(text: "正在检查……")
        case .working(let text):
            Working(text: text)
        case .needInstall:
            Message(symbol: "arrow.down.circle", title: "第一步：安装鼠须管",
                    lines: ["鼠须管是 Rime 输入法在 Mac 上的版本。应用会从官方 GitHub 下载最新的安装包，检查签名和公证，然后安装。",
                            "安装时会弹出系统授权框，需要输入这台 Mac 的登录密码。"])
            Button("安装鼠须管") { Task { await flow.install() } }
                .buttonStyle(.borderedProminent)
        case .needInputMethod(let note):
            Message(symbol: "keyboard", title: "第二步：添加输入法",
                    lines: ["macOS 不允许应用自己添加输入法，要你在系统设置里加一次：",
                            "「键盘 → 文字输入 → 输入法 → 编辑… → + → 简体中文 → 鼠须管」",
                            "点下面的按钮会打开系统设置；加好后应用会自动继续。"])
            if let note { Note(text: note) }
            Button("打开系统设置") { Task { await flow.addInputMethod() } }
                .buttonStyle(.borderedProminent)
        case .waitingForInputMethod:
            Working(text: "请在系统设置里添加「鼠须管」（简体中文下面）。加好后这里会自动继续……\n加好了很久还没继续的话，请退出应用再打开。")
        case .needRestart:
            Message(symbol: "arrow.clockwise", title: "请退出应用再打开",
                    lines: ["系统里鼠须管的输入源丢了，已经重新注册。要退出这个应用再重新打开，才能看到最新的状态。"])
            Button("退出应用") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderedProminent)
        case .chooseStart(let choice):
            chooseStart(choice)
        case .done(let lines):
            Message(symbol: "checkmark.circle", title: "设置好了", lines: lines)
            Button("开始使用") { onFinish(lines) }
                .buttonStyle(.borderedProminent)
        case .failed(let message):
            Message(symbol: "exclamationmark.triangle", title: "出了点问题", lines: [message])
            Button("重试") { Task { await flow.start() } }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder func chooseStart(_ choice: StartChoice) -> some View {
        switch choice {
        case .empty:
            Message(symbol: "sparkles", title: "第三步：选一个起步方案",
                    lines: ["以后可以随时在应用里改方案、调外观。用过这个应用、手里有导出文件的话，也可以直接导入。"])
            starterButtons
        case .unrecognized:
            Message(symbol: "questionmark.folder", title: "第三步：选一个起步方案",
                    lines: ["Rime 目录里已经有配置，但里面的方案这个应用还不认识。",
                            "选一个起步方案后，原来的文件会先完整备份（这份备份永久保留），认不出的文件原样留着。"])
            starterButtons
        case .existing(let summary):
            Message(symbol: "doc.text.magnifyingglass", title: "第三步：接管已有的配置",
                    lines: ["Rime 目录里已经有配置。下面是应用认出来的内容，和接管后会变的文件。确认后才会改：会先完整备份（这份备份永久保留）。"])
            TakeoverPreviewView(summary: summary)
            HStack {
                Button("接管") { Task { await flow.confirmTakeover() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!summary.canConfirm)
                Menu("改用起步方案") {
                    ForEach(Starter.allCases, id: \.self) { starter in
                        Button(starter.displayName) { Task { await flow.useSettings(.starter(starter)) } }
                    }
                }
                .fixedSize()
                Button("从导出文件导入…") { importing = true }
            }
        }
    }

    var starterButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Starter.allCases, id: \.self) { starter in
                Button(starter.displayName) { Task { await flow.useSettings(.starter(starter)) } }
            }
            Divider()
            Button("从导出文件导入…") { importing = true }
        }
    }
}

struct Message: View {
    let symbol: String
    let title: String
    let lines: [String]

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title2.bold())
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Working: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Note: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
