// 测试工具：查看/启用/选中输入法（Text Input Sources），只在测试虚拟机里用
import Carbon
import Foundation

func prop<T>(_ src: TISInputSource, _ key: CFString) -> T? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
}

func sources(includeAll: Bool) -> [TISInputSource] {
    (TISCreateInputSourceList(nil, includeAll)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

func describe(_ s: TISInputSource) -> String {
    let id: String = prop(s, kTISPropertyInputSourceID) ?? "?"
    let name: String = prop(s, kTISPropertyLocalizedName) ?? "?"
    let enabled = (prop(s, kTISPropertyInputSourceIsEnabled) as Bool?) ?? false
    let selected = (prop(s, kTISPropertyInputSourceIsSelected) as Bool?) ?? false
    let selectable = (prop(s, kTISPropertyInputSourceIsSelectCapable) as Bool?) ?? false
    return "\(id)\t\(name)\tenabled=\(enabled)\tselected=\(selected)\tselectable=\(selectable)"
}

let args = CommandLine.arguments.dropFirst()
let cmd = args.first ?? "list"
let filter = args.dropFirst().first

switch cmd {
case "list":   // 已安装的（含未启用的），可按 ID 关键字过滤
    for s in sources(includeAll: true) {
        let line = describe(s)
        if let f = filter, !line.lowercased().contains(f.lowercased()) { continue }
        print(line)
    }
case "enabled":  // 当前启用的
    for s in sources(includeAll: false) { print(describe(s)) }
case "current":
    print(describe(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
case "enable", "select":
    guard let f = filter else { print("需要 ID 关键字"); exit(2) }
    // 以 = 开头表示 ID 精确匹配，否则按包含匹配
    let matches = sources(includeAll: true).filter {
        let id = (prop($0, kTISPropertyInputSourceID) as String?) ?? ""
        return f.hasPrefix("=") ? id == String(f.dropFirst()) : id.contains(f)
    }
    for s in matches {
        let err = cmd == "enable" ? TISEnableInputSource(s) : TISSelectInputSource(s)
        print("\(cmd) \(describe(s)) -> OSStatus \(err)")
    }
default:
    print("用法: tis-probe list [关键字] | enabled | current | enable <ID关键字> | select <ID关键字>")
}
