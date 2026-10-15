import Testing
@testable import RimeKit

@Suite struct SquirrelControlTests {
    @Test func 退出鼠须管时只把没在运行当成正常() {
        #expect(!SquirrelControl.quitFailed(status: 0, stderr: ""))
        #expect(!SquirrelControl.quitFailed(status: 1, stderr: "No matching processes belonging to you were found\n"))
        #expect(SquirrelControl.quitFailed(status: 1, stderr: "killall: permission denied\n"))
    }
}
