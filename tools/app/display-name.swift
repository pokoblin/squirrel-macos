// 用法：swift displayname.swift <.app 路径> <语言>，打出这个语言下访达显示的名字（不运行应用）
import Foundation
let args = CommandLine.arguments
UserDefaults.standard.set([args[2]], forKey: "AppleLanguages")
let url = URL(fileURLWithPath: args[1])
let bundle = Bundle(url: url)!
let preferred = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [args[2]])
var name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? "?"
if let loc = preferred.first, let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: loc),
   let dict = NSDictionary(contentsOfFile: path), let local = dict["CFBundleDisplayName"] as? String {
    name = local
}
print("\(args[2]) → \(name)")
