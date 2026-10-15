// 测试工具：验证独立的 .app 能不能读 macOS「文本替换」数据库。
// 只输出条数和错误信息，不输出任何内容。结果写到 /tmp/tr-probe-result.txt。
import Foundation
import SQLite3

let path = NSHomeDirectory() + "/Library/KeyboardServices/TextReplacements.db"
var lines: [String] = []
lines.append("path_exists=\(FileManager.default.fileExists(atPath: path))")
lines.append("readable=\(FileManager.default.isReadableFile(atPath: path))")

var db: OpaquePointer?
let openRC = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
lines.append("open_rc=\(openRC)")
if openRC == SQLITE_OK {
    var stmt: OpaquePointer?
    let sql = "SELECT count(*) FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0 OR ZWASDELETED IS NULL"
    let prepareRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    lines.append("prepare_rc=\(prepareRC)")
    if prepareRC == SQLITE_OK {
        let stepRC = sqlite3_step(stmt)
        lines.append("step_rc=\(stepRC)")
        if stepRC == SQLITE_ROW { lines.append("count=\(sqlite3_column_int(stmt, 0))") }
    } else {
        lines.append("error=\(String(cString: sqlite3_errmsg(db)))")
    }
    sqlite3_finalize(stmt)
} else if let db {
    lines.append("error=\(String(cString: sqlite3_errmsg(db)))")
}
sqlite3_close(db)

let result = lines.joined(separator: "\n") + "\n"
try? result.write(toFile: "/tmp/tr-probe-result.txt", atomically: true, encoding: .utf8)
