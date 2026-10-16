import Foundation
import Testing
@testable import RimeKit

@Suite struct PreviewProtocolTests {
    @Test func 请求编码成一行带op的JSON() throws {
        let line = String(decoding: try PreviewLine.encode(PreviewRequest.open(userDir: "/tmp/a", schema: "py")), as: UTF8.self)
        #expect(line.hasSuffix("\n") && !line.dropLast().contains("\n"))
        let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        #expect(obj["op"] as? String == "open" && obj["userDir"] as? String == "/tmp/a" && obj["schema"] as? String == "py")
    }

    @Test(arguments: [PreviewRequest.open(userDir: "/x", schema: "s"), .input("nihao"), .key(.pageDown), .select(2), .clear])
    func 请求往返不变(_ r: PreviewRequest) throws {
        #expect(try PreviewLine.decode(PreviewRequest.self, from: String(decoding: PreviewLine.encode(r), as: UTF8.self)) == r)
    }

    @Test func 键码() {
        #expect(PreviewKey.backspace.keysym == 0xff08)
        #expect(PreviewKey.pageDown.keysym == 0xff56)
        #expect(PreviewKey.return.keysym == 0xff0d)
    }

    @Test func 不认识的op解码失败() {
        #expect(throws: (any Error).self) { try PreviewLine.decode(PreviewRequest.self, from: #"{"op":"jump"}"#) }
    }

    @Test func 设计里的结果例子能解码() throws {
        let r = try PreviewLine.decode(PreviewResponse.self, from: #"{"ok":true,"librimeVersion":"1.16.0","state":{"committed":"你好","preedit":"ni hao","cursor":6,"candidates":[{"text":"你好","comment":""}],"labels":null,"pageNo":0,"isLastPage":false,"highlighted":0}}"#)
        #expect(r.state?.committed == "你好" && r.state?.candidates.first?.text == "你好" && r.librimeVersion == "1.16.0")
    }

    @Test func 出错结果() throws {
        let r = try PreviewLine.decode(PreviewResponse.self, from: String(decoding: PreviewLine.encode(PreviewResponse.failure(.schemaMissing, "没有 xx")), as: UTF8.self))
        #expect(!r.ok && r.error == PreviewFailure(kind: .schemaMissing, message: "没有 xx"))
    }
}
