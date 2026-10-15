import CryptoKit
import Foundation

enum Hashing {
    static func sha256(of file: URL) throws -> String {
        sha256(of: try Data(contentsOf: file))
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
