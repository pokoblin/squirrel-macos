import Foundation

/// 点分数字的版本号，例如 0.10.0。带 -rc1 这类后缀时只看前面的数字；缺的段当 0（1.0 == 1.0.0）
public struct AppVersion: Sendable, Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let core = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let pieces = core.split(separator: ".", omittingEmptySubsequences: false)
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(piece) else { return nil }
            parts.append(n)
        }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    /// 这个应用的版本（AppInfo.version 有测试保证能解析）
    public static var current: AppVersion { AppVersion(AppInfo.version)! }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        compare(a, b) < 0
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        compare(a, b) == 0
    }

    private static func compare(_ a: AppVersion, _ b: AppVersion) -> Int {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}
