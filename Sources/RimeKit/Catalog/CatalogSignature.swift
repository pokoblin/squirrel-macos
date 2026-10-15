import CryptoKit
import Foundation

/// 在线方案清单的签名（在线方案清单设计 5.1、5.2）：Ed25519，签的是清单文件的原始字节；签名文件是一行 base64
public enum CatalogSignature {
    /// 正式公钥（base64，32 字节）。私钥在宿主机登录钥匙串里，用 tools/catalog/keygen.sh 生成。
    /// 空的时候任何在线清单都验不过，应用只用内置清单
    static let publicKeys: [String] = []

    /// 认哪些公钥。debug 编译时多认环境变量 RIMEKIT_CATALOG_TEST_PUBKEY 里的测试公钥（测试机实测用）；release 编译没有这段
    public static var trustedKeys: [Data] {
        var keys = publicKeys.compactMap { Data(base64Encoded: $0) }
        #if DEBUG
        if let extra = ProcessInfo.processInfo.environment["RIMEKIT_CATALOG_TEST_PUBKEY"], let key = Data(base64Encoded: extra) {
            keys.append(key)
        }
        #endif
        return keys
    }

    /// signature 是签名文件的内容（base64 文本，前后可以有空白）
    public static func verify(_ data: Data, signature: Data, keys: [Data]) -> Bool {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: text) else { return false }
        return keys.contains { key in
            guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { return false }
            return publicKey.isValidSignature(raw, for: data)
        }
    }

    /// 返回签名文件的内容
    public static func sign(_ data: Data, privateKey: Data) throws -> Data {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return Data((try key.signature(for: data).base64EncodedString() + "\n").utf8)
    }

    /// 生成一对密钥（base64）：私钥存进钥匙串，公钥写进 publicKeys
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }
}
