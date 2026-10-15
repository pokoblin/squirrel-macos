import Foundation
@testable import RimeKit

/// 假的 rime_dict_manager：输入习惯存在内存里；前几次调用可以假装被鼠须管占着
final class FakeUserDBTool: UserDBTool, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String]
    private var failures: Int
    private var log: [String] = []

    init(dbs: [String: String] = [:], lockedFailures: Int = 0) {
        stored = dbs
        failures = lockedFailures
    }

    var dbs: [String: String] { lock.withLock { stored } }
    var calls: [String] { lock.withLock { log } }

    func list() throws -> [String] { lock.withLock { stored.keys.sorted() } }

    func export(_ name: String, to file: URL) throws {
        let text: String? = try lock.withLock {
            if failures > 0 { failures -= 1; throw UserDBError.locked(name) }
            log.append("export \(name)")
            return stored[name]
        }
        guard let text else { throw UserDBError.failed(name, "没有这个输入习惯") }
        try Data(text.utf8).write(to: file)
    }

    func importSnapshot(_ name: String, from file: URL) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        try lock.withLock {
            if failures > 0 { failures -= 1; throw UserDBError.locked(name) }
            log.append("import \(name)")
            stored[name] = (stored[name] ?? "") + text
        }
    }
}
