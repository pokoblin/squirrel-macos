import Foundation
@testable import RimeKit

enum InstallFixtures {
    static func pkgURL(_ version: String) -> URL {
        URL(string: "https://github.com/rime/squirrel/releases/download/\(version)/Squirrel-\(version).pkg")!
    }

    static func releaseJSON(version: String, digest: String?, assetName: String? = nil) -> Data {
        let name = assetName ?? "Squirrel-\(version).pkg"
        let digestField = digest.map { #","digest":"sha256:\#($0)""# } ?? ""
        return Data(#"""
        {"tag_name":"\#(version)","assets":[{"name":"\#(name)","browser_download_url":"\#(pkgURL(version).absoluteString)","size":1\#(digestField)}]}
        """#.utf8)
    }

    /// 在假的 Squirrel.app 里写 Info.plist，模拟装好了某个版本
    static func writeInfoPlist(app: URL, version: String) throws {
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleVersion": version, "CFBundleIdentifier": "im.rime.inputmethod.Squirrel"],
            format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
    }
}
