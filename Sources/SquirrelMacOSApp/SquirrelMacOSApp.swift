import AppCore
import AppUI
import RimeKit
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    @State private var state: AppState? = try? AppState(env: AppEnvironment.live())

    var body: some Scene {
        // 只有一个窗口：不会出现两个引导同时在跑
        Window(Self.title, id: "main") {
            RootView(state: state)
        }
        .windowResizability(.contentSize)
    }

    /// 窗口标题跟着系统语言：中文系统「鼠须管助手」，其他 SquirrelHelper（Info.plist 和 *.lproj/InfoPlist.strings）
    static var title: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String ?? AppInfo.name
    }
}
