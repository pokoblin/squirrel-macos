import Foundation

/// 测试用的临时目录，每个测试一个，用完调用 remove()
struct TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "rimekit-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
