import Foundation

/// 鼠须管的版本号，例如 1.1.2。按数字逐段比较，缺的段当 0。
public struct SquirrelVersion: Comparable, Sendable, CustomStringConvertible {
    let parts: [Int]
    public let description: String

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
        self.description = trimmed
    }

    public static func < (a: SquirrelVersion, b: SquirrelVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: SquirrelVersion, b: SquirrelVersion) -> Bool {
        !(a < b) && !(b < a)
    }
}
