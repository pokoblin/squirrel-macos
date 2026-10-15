import Foundation
import RimeKit

/// 导出时保存对话框里的默认文件名：带上当前时间，多次导出不会重名（时间用点隔开，和 macOS 截屏一样）
public enum ExportFileName {
    public static func suggested(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(AppInfo.name) 导出 \(formatter.string(from: date)).zip"
    }
}
