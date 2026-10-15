import CryptoKit
import Foundation

enum Hashing {
    static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
