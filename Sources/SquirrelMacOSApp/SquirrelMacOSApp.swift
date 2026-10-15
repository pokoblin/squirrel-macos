import AppUI
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    var body: some Scene {
        WindowGroup("squirrel-macos") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}
