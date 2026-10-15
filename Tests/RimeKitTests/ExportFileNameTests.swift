import Foundation
import Testing
@testable import AppCore

@Suite struct ExportFileNameTests {
    @Test func 默认文件名带上当前时间() throws {
        // 多次导出不会重名，看文件名就知道是什么时候导出的（时间用点隔开，和 macOS 截屏一样）
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(ExportFileName.suggested(at: Date(timeIntervalSince1970: 1_800_000_000), timeZone: utc)
                == "鼠须管助手 导出 2027-01-15 08.00.00.zip")
    }
}
