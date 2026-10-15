import AppCore
import AppUI
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    @State private var state: AppState? = try? AppState(env: AppEnvironment.live())

    var body: some Scene {
        // 只有一个窗口：不会出现两个引导同时在跑
        Window("squirrel-macos", id: "main") {
            RootView(state: state)
        }
        .windowResizability(.contentSize)
    }
}
