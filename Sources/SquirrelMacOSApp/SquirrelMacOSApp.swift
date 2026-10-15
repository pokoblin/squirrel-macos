import AppCore
import AppUI
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    @State private var flow: SetupFlow? = try? SetupFlow(env: AppEnvironment.live())

    var body: some Scene {
        WindowGroup("squirrel-macos") {
            RootView(flow: flow)
        }
        .windowResizability(.contentSize)
    }
}
