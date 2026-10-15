import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogSignatureTests {
    let pair = CatalogSignature.generateKeyPair()
    var publicKey: Data { Data(base64Encoded: pair.publicKey)! }
    var privateKey: Data { Data(base64Encoded: pair.privateKey)! }
    let data = Data(#"{"formatVersion":1,"serial":1,"packages":[]}"#.utf8)

    @Test func 签名对的能通过() throws {
        let sig = try CatalogSignature.sign(data, privateKey: privateKey)
        #expect(CatalogSignature.verify(data, signature: sig, keys: [publicKey]))
    }

    @Test func 内容改了一个字节就不通过() throws {
        let sig = try CatalogSignature.sign(data, privateKey: privateKey)
        var changed = data
        changed[changed.count - 2] ^= 1
        #expect(!CatalogSignature.verify(changed, signature: sig, keys: [publicKey]))
    }

    @Test func 签名乱码或空的不通过() {
        #expect(!CatalogSignature.verify(data, signature: Data("不是签名".utf8), keys: [publicKey]))
        #expect(!CatalogSignature.verify(data, signature: Data(), keys: [publicKey]))
    }

    @Test func 别的密钥签的不通过_认了那把公钥才通过() throws {
        let other = CatalogSignature.generateKeyPair()
        let sig = try CatalogSignature.sign(data, privateKey: Data(base64Encoded: other.privateKey)!)
        #expect(!CatalogSignature.verify(data, signature: sig, keys: [publicKey]))
        #expect(CatalogSignature.verify(data, signature: sig, keys: [publicKey, Data(base64Encoded: other.publicKey)!]))
    }

    @Test func 没有公钥时什么都不通过() throws {
        let sig = try CatalogSignature.sign(data, privateKey: privateKey)
        #expect(!CatalogSignature.verify(data, signature: sig, keys: []))
    }

    @Test func 签名文件是一行base64() throws {
        let text = String(decoding: try CatalogSignature.sign(data, privateKey: privateKey), as: UTF8.self)
        #expect(text.hasSuffix("\n"))
        #expect(Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))?.count == 64)
    }

    @Test func 私钥不对时报错() {
        #expect(throws: (any Error).self) { try CatalogSignature.sign(data, privateKey: Data("短".utf8)) }
    }

    @Test func 正式公钥能解析() {
        #expect(CatalogSignature.publicKeys.count == 1)
        #expect(CatalogSignature.publicKeys.allSatisfy { Data(base64Encoded: $0)?.count == 32 })
    }
}
