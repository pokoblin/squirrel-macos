import AppCore
import AppUI
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    @State private var flow: SetupFlow? = try? SetupFlow(env: AppEnvironment.live())

    var body: some Scene {
        // 只有一个窗口：不会出现两个引导同时在跑
        Window("squirrel-macos", id: "main") {
            RootView(flow: flow)
        }
        .windowResizability(.contentSize)
    }
}
