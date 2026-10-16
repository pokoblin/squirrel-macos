import Darwin
import Foundation
import RimePreviewProtocol

// 试打预览的辅助程序：从 stdin 一行读一个请求，往 stdout 一行写一个结果（协议见 RimePreviewProtocol）。
// 用法：rime-preview-helper [--squirrel <Squirrel.app>]
// stdin 关掉就 finalize 后退出，所以应用退出或崩溃时它也跟着结束。

// 留一份 stdout 只给协议用，再把 fd 1 指向 stderr：
// librime、Lua 脚本里的 print 往 stdout 写的东西都进 stderr，不会搞乱协议
let protocolOut = dup(1)
dup2(2, 1)
// 应用那边关掉管道时 write 返回错误，而不是被 SIGPIPE 直接杀掉
signal(SIGPIPE, SIG_IGN)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var squirrelApp = URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app")
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--squirrel":
        guard let path = arguments.popFirst() else { fail("--squirrel 后面要跟 Squirrel.app 的路径") }
        squirrelApp = URL(fileURLWithPath: path)
    default:
        fail("用法：rime-preview-helper [--squirrel <Squirrel.app>]；不认识的参数：\(argument)")
    }
}

/// 把一行结果整个写出去；写不出去（应用那边关了）就退出
func reply(_ response: PreviewResponse) {
    let data = (try? PreviewLine.encode(response))
        ?? Data(#"{"error":{"kind":"badRequest","message":"结果编码失败"},"ok":false}"#.utf8 + [0x0a])
    var offset = 0
    while offset < data.count {
        let n = data.withUnsafeBytes { write(protocolOut, $0.baseAddress! + offset, data.count - offset) }
        if n < 0 {
            if errno == EINTR { continue }
            exit(1)
        }
        offset += n
    }
}

// 先加载 librime（还不初始化），等第一条 open
let engine = RimeEngine(squirrelApp: squirrelApp)

while let line = readLine(strippingNewline: true) {
    guard let request = try? PreviewLine.decode(PreviewRequest.self, from: line) else {
        reply(.failure(.badRequest, "看不懂的请求"))
        continue
    }
    switch request {
    case let .open(userDir, schema): reply(engine.open(userDir: userDir, schema: schema))
    case let .input(text): reply(engine.input(text))
    case let .key(key): reply(engine.key(key))
    case let .select(index): reply(engine.select(index))
    case .clear: reply(engine.clear())
    }
}
engine.shutdown()
exit(0)
