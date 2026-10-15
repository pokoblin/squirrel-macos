import Foundation
import Testing
@testable import RimeKit

@Suite struct AppPathsTests {
    @Test func 默认目录在应用支持目录下() {
        let path = AppPaths.default.root.path
        #expect(path.hasSuffix("/Library/Application Support/squirrel-macos"))
    }

    @Test func 子目录都在根目录下() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/x", isDirectory: true))
        #expect(paths.packages.path == "/tmp/x/packages")
        #expect(paths.staging.path == "/tmp/x/staging")
    }
}
