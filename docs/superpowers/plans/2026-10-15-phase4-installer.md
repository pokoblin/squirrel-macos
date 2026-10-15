# 阶段 4：安装鼠须管、启用输入法、环境检查 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在一台什么都没装的 Mac 上，`rimectl install` 能下载、校验、安装鼠须管；`rimectl activate` 能打开系统设置、等用户添加好输入法、切换过去并启动鼠须管；`rimectl doctor` 能逐项检查环境并告诉用户下一步做什么（设计 6.2 第 1 步）。

**Architecture:** 新增 `Install/` 目录：`SquirrelRelease`（从 GitHub 取最新版本、下载地址、sha256）、`SquirrelVersion`（版本比较）、`PackageVerifier`（sha256 + `pkgutil` + `spctl` 三道检查）、`PrivilegedInstaller`（系统授权框 / 免密 sudo）、`SquirrelInstaller`（串起来）、`InputSource`（Carbon TIS：查状态、切换、打开系统设置、等待时让 run loop 转）、`SquirrelActivator`（启用流程）、`Doctor`（环境检查）。会碰系统的部分都通过协议注入，宿主机只测假的；真实流程在**新克隆的干净测试机**里跑。

**Tech Stack:** Swift 6.4、Swift Testing、Carbon（TIS）、Foundation（`NSAppleScript`、`PropertyListSerialization`）、系统自带 `/usr/sbin/pkgutil`、`/usr/sbin/spctl`、`/usr/sbin/installer`、`/usr/bin/sudo`、`/usr/bin/open`。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 2、3、6.2、7、10 节）；事实 [docs/verified-facts.md](../../verified-facts.md)、[docs/install-test-log.md](../../install-test-log.md)、[docs/phase0-log.md](../../phase0-log.md)；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## Global Constraints

- 宿主机**绝不安装、不卸载鼠须管，不改输入法状态**。宿主机测试只用假的安装器和输入法服务；联网测试只下载安装包到临时目录做校验（只读运行 `pkgutil`、`spctl`）。
- 真实安装、启用只在测试机里做：新克隆一台干净的 `squirrel-fresh` 跑完整流程，测完删掉（`squirrel-dev` 继续保留；同时最多两台测试机）。登录桌面、输入授权密码、在系统设置里添加输入法由用户亲手做。
- 安装包必须**三道检查都过**才安装（已实测：改了 1 个字节的包 `spctl` 照样 `accepted`，只有 `pkgutil` 能发现）：
  1. sha256 等于 GitHub 接口给的 `digest`（接口没给就跳过这一道，但另外两道必须过）
  2. `pkgutil --check-signature` 退出码 0，并且有 `Status: signed by a developer certificate issued by Apple for distribution`、`Notarization: trusted by the Apple notary service`，证书链第 1 张是 `Developer ID Installer: … (28HU5A7B46)`
  3. `spctl -a -vv -t install` 退出码 0，输出有 `: accepted` 和 `source=Notarized Developer ID`
- 已安装的版本读 `Squirrel.app/Contents/Info.plist` 的 `CFBundleVersion`（1.1.2 没有 `CFBundleShortVersionString`，已实测）。已装了同版本或更新的就不重装（`--force` 除外）；鼠须管自带 Sparkle，会自己升级。
- 判断「用户添加好了没有」看主输入源 `im.rime.inputmethod.Squirrel` 的 `kTISPropertyInputSourceIsEnabled`（不读偏好文件）；添加好后切换到 `im.rime.inputmethod.Squirrel.Hans`，鼠须管没运行就 `open` 启动它（切换后它不会自己启动，已实测）。
- 打开系统设置用 `x-apple.systempreferences:com.apple.Keyboard-Settings.extension`（已实测直接停在键盘页）。
- 安装和应用配置共用一把锁（`ApplyLock`）。
- 用简单直白的中文写错误信息和命令行输出。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 下载到的安装包被改过、或者是别人签名的、或者没公证 → 绝不安装，什么都不动（任务 3、4 有测试，任务 8 联网实测改过的包）。
2. 用户在系统授权框点了「取消」→ 说清楚是取消了，不算出错，什么都不动（任务 4 有测试，任务 8 实测）。
3. 用户迟迟不在系统设置里添加 → 到时间就停下并说明怎么继续，不会一直卡住（任务 5 有测试）。
4. 应用一直开着、每秒查一次，能不能看到用户刚在系统设置里做的添加（同一个进程里的缓存）→ 任务 1 先实测，任务 5 按结果实现，任务 8 再实测。
5. 已经装过（同版本或更新版本）→ 不重新下载安装（任务 4 有测试）。

---

## 文件结构

```
Sources/RimeKit/
  Deploy/RimeLocations.swift        # 加 installedSquirrelVersion
  Install/SquirrelVersion.swift     # 版本号比较
  Install/SquirrelRelease.swift     # 从 GitHub 取最新版本
  Install/PackageVerifier.swift     # 三道检查
  Install/PrivilegedInstaller.swift # 系统授权框 / 免密 sudo
  Install/SquirrelInstaller.swift   # 下载、检查、安装
  Install/InputSource.swift         # TIS：状态、切换、打开设置、等待
  Install/SquirrelActivator.swift   # 启用流程
  Install/Doctor.swift              # 环境检查
Sources/rimectl/Rimectl.swift       # install、activate、doctor
tools/vm/tis-probe.swift            # 加 watch（任务 1 实测用）
Tests/RimeKitTests/
  Support/InstallFakes.swift
  SquirrelReleaseTests.swift
  PackageVerifierTests.swift
  SquirrelInstallerTests.swift
  SquirrelActivatorTests.swift
  DoctorTests.swift
  RimectlInstallTests.swift
  OnlineInstallerTests.swift
docs/phase4-vm-log.md
```

---

### Task 1: 实测：同一个进程里每秒查一次，能不能看到用户刚做的添加

**Files:**
- Modify: `tools/vm/tis-probe.swift`（加 `watch` 命令）
- Create: `docs/phase4-vm-log.md`

**Interfaces:**
- Produces: `tis-probe watch <pump|sleep> <秒数>`：同一个进程里每秒查一次主输入源的 enabled，变化时打印一行 `时间 enabled=…`。`pump` 每次等待用 `CFRunLoopRunInMode`（让系统通知进来），`sleep` 用 `Thread.sleep`。结论决定任务 5 里 `pump` 的实现。

- [ ] **Step 1: 在 `tis-probe.swift` 的 `switch cmd` 里，`default:` 前面加**

```swift
case "watch":   // watch <pump|sleep> <秒数>：同一个进程里反复查主输入源有没有启用
    let mode = filter ?? "pump"
    let seconds = Int(args.dropFirst(2).first ?? "120") ?? 120
    func mainEnabled() -> Bool {
        let main = sources(includeAll: true).first { (prop($0, kTISPropertyInputSourceID) as String?) == "im.rime.inputmethod.Squirrel" }
        return main.map { (prop($0, kTISPropertyInputSourceIsEnabled) as Bool?) ?? false } ?? false
    }
    var last: Bool? = nil
    for i in 0..<seconds {
        let now = mainEnabled()
        if now != last {
            print("\(i)s [\(mode)] enabled=\(now)")
            fflush(stdout)
            last = now
        }
        if mode == "pump" {
            _ = CFRunLoopRunInMode(.defaultMode, 1.0, false)
        } else {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
    print("结束 [\(mode)] enabled=\(mainEnabled())")
```

并把 `default:` 里的用法说明加上 `| watch <pump|sleep> <秒数>`。

Run: `swiftc -O tools/vm/tis-probe.swift -o tools/vm/tis-probe 2>&1 | tail -2`
Expected: 编译通过。

- [ ] **Step 2: 在 `squirrel-dev` 里同时跑两种等法，请用户先删掉再加回鼠须管**

先在后台同时启动两个（各 150 秒）：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'P="/Volumes/My Shared Files/vm/tis-probe"; (sudo launchctl asuser $(id -u) sudo -u tester "$P" watch pump 150 > /tmp/watch-pump.txt 2>&1 &); (sudo launchctl asuser $(id -u) sudo -u tester "$P" watch sleep 150 > /tmp/watch-sleep.txt 2>&1 &); sleep 2; cat /tmp/watch-pump.txt /tmp/watch-sleep.txt'
```

Expected：两个都打印 `0s [...] enabled=true`。然后请用户在测试机的「系统设置 → 键盘 → 文字输入 → 编辑…」里选中「鼠须管」，点「−」删掉；等 10 秒；再点「+ → 简体中文 → 鼠须管」加回来。用户说做完后：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'sleep 5; echo "== pump"; cat /tmp/watch-pump.txt; echo "== sleep"; cat /tmp/watch-sleep.txt'
```

- [ ] **Step 3: 记录结论**

建 `docs/phase4-vm-log.md`，第一节「实测 1：同一个进程里能不能看到添加」：两种等法各自打印了什么。三种可能：
- `pump` 看到了 false → true，`sleep` 没看到：任务 5 的 `pump` 按计划用 `CFRunLoopRunInMode`。
- 两种都看到了：同样用 `CFRunLoopRunInMode`（多一层保险）。
- 两种都没看到：任务 5 改成每次查状态都新开一个子进程（`rimectl input-state`，输出 JSON），在执行记录里写 Ruling，并相应修改任务 5、7 的代码。

- [ ] **Step 4: 提交**

```bash
git add tools/vm/tis-probe.swift docs/phase4-vm-log.md
git commit -m "tools: tis-probe watch；实测同一进程里能否看到输入法添加

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 版本号、最新版本、已安装的版本

**Files:**
- Create: `Sources/RimeKit/Install/SquirrelVersion.swift`
- Create: `Sources/RimeKit/Install/SquirrelRelease.swift`
- Modify: `Sources/RimeKit/Deploy/RimeLocations.swift`（加 `installedSquirrelVersion`）
- Create: `Tests/RimeKitTests/Support/InstallFakes.swift`（本任务先放发布信息的假数据和写 Info.plist 的辅助）
- Test: `Tests/RimeKitTests/SquirrelReleaseTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`、`RetryPolicy`、`withRetry`（阶段 1）、`RimeLocations`（阶段 3）。
- Produces:
  - `public struct SquirrelVersion: Comparable, Sendable, CustomStringConvertible { init?(_ text: String) }`（去掉开头的 `v`，按点分成数字比较，`1.10 > 1.9`，`1.1 == 1.1.0`）
  - `public struct SquirrelRelease: Sendable, Equatable { version: String; downloadURL: URL; sha256: String? }`
  - `public enum SquirrelReleaseError: Error, Equatable, CustomStringConvertible { case noPackage, badResponse }`
  - `public struct SquirrelReleaseSource: Sendable { static let latestURL: URL; init(http:retry:); func latest() async throws -> SquirrelRelease }`（读 `tag_name`，附件里找 `Squirrel-*.pkg`，`digest` 形如 `sha256:<hex>`）
  - `RimeLocations.installedSquirrelVersion: String?`
  - 测试辅助：`InstallFixtures.releaseJSON(version:digest:assetName:)`、`InstallFixtures.pkgURL(_ version:)`、`InstallFixtures.writeInfoPlist(app:version:)`

- [ ] **Step 1: 写测试辅助 `Tests/RimeKitTests/Support/InstallFakes.swift`**

```swift
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
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/SquirrelReleaseTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelReleaseTests {
    @Test func 版本号比较() throws {
        let v = { (s: String) in try #require(SquirrelVersion(s)) }
        #expect(try v("1.1.2") > v("1.1.1"))
        #expect(try v("1.10") > v("1.9"))
        #expect(try v("v1.2") == v("1.2.0"))
        #expect(try v("1.1") == v("1.1.0"))
        #expect(SquirrelVersion("abc") == nil)
        #expect(SquirrelVersion("") == nil)
        #expect(try v("v1.2").description == "1.2")
    }

    @Test func 读最新版本() async throws {
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: "ABCDEF")))
        let r = try await SquirrelReleaseSource(http: http, retry: .immediate).latest()
        #expect(r == SquirrelRelease(version: "1.1.2", downloadURL: InstallFixtures.pkgURL("1.1.2"), sha256: "abcdef"))
    }

    @Test func 没有digest时sha256为空() async throws {
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: nil)))
        #expect(try await SquirrelReleaseSource(http: http, retry: .immediate).latest().sha256 == nil)
    }

    @Test func 没有安装包() async {
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: nil, assetName: "notes.txt")))
        await #expect(throws: SquirrelReleaseError.noPackage) {
            try await SquirrelReleaseSource(http: http, retry: .immediate).latest()
        }
    }

    @Test func 读已安装的版本() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var l = try DeployFixtures.locations(dir)
        #expect(l.installedSquirrelVersion == nil)
        try InstallFixtures.writeInfoPlist(app: l.squirrelApp, version: "1.1.2")
        #expect(l.installedSquirrelVersion == "1.1.2")
        l.squirrelApp = dir.url.appending(path: "None.app")
        #expect(l.installedSquirrelVersion == nil)
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter SquirrelReleaseTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SquirrelVersion' in scope`（或 `SquirrelReleaseSource`）。

- [ ] **Step 4: 写 `Sources/RimeKit/Install/SquirrelVersion.swift`**

```swift
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
```

- [ ] **Step 5: 写 `Sources/RimeKit/Install/SquirrelRelease.swift`**

```swift
import Foundation

public struct SquirrelRelease: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL
    /// GitHub 给的 sha256（小写十六进制）；接口没给时为空
    public let sha256: String?

    public init(version: String, downloadURL: URL, sha256: String?) {
        self.version = version
        self.downloadURL = downloadURL
        self.sha256 = sha256
    }
}

public enum SquirrelReleaseError: Error, Equatable, Sendable, CustomStringConvertible {
    case noPackage
    case badResponse

    public var description: String {
        switch self {
        case .noPackage: return "鼠须管最新的发布里找不到安装包（Squirrel-*.pkg）"
        case .badResponse: return "看不懂 GitHub 返回的鼠须管发布信息"
        }
    }
}

/// 从 GitHub 取鼠须管最新的正式版本
public struct SquirrelReleaseSource: Sendable {
    public static let latestURL = URL(string: "https://api.github.com/repos/rime/squirrel/releases/latest")!

    let http: any HTTPClient
    let retry: RetryPolicy

    public init(http: any HTTPClient, retry: RetryPolicy = .standard) {
        self.http = http
        self.retry = retry
    }

    public func latest() async throws -> SquirrelRelease {
        let http = self.http
        let url = Self.latestURL
        let data = try await withRetry(retry) { try await http.get(url) }
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw SquirrelReleaseError.badResponse
        }
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Squirrel-") && $0.name.hasSuffix(".pkg") }) else {
            throw SquirrelReleaseError.noPackage
        }
        let sha = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        return SquirrelRelease(version: release.tagName, downloadURL: asset.downloadURL, sha256: sha)
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: URL
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name, digest
                case downloadURL = "browser_download_url"
            }
        }
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case assets
            case tagName = "tag_name"
        }
    }
}
```

- [ ] **Step 6: `RimeLocations.swift` 里 `squirrelInstalled` 后面加**

```swift
    /// 已安装的鼠须管版本（Info.plist 的 CFBundleVersion；1.1.2 没有 CFBundleShortVersionString）
    public var installedSquirrelVersion: String? {
        let plist = squirrelApp.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (dict["CFBundleVersion"] as? String) ?? (dict["CFBundleShortVersionString"] as? String)
    }
```

- [ ] **Step 7: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test|Expectation failed" | head -5`
Expected: 全部通过（新增 5 个）。

- [ ] **Step 8: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 鼠须管版本比较、从 GitHub 取最新版本、读已安装的版本

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 安装包的三道检查

**Files:**
- Create: `Sources/RimeKit/Install/PackageVerifier.swift`
- Test: `Tests/RimeKitTests/PackageVerifierTests.swift`

**Interfaces:**
- Consumes: `Shell`、`Hashing`。
- Produces:
  - `public enum VerificationError: Error, Equatable, CustomStringConvertible { case checksumMismatch(expected: String, actual: String), invalidPackage(String), notDeveloperID, notNotarized, wrongTeam(String?), gatekeeperRejected(String) }`
  - `public protocol PackageVerifying: Sendable { func verify(_ pkg: URL, sha256: String?) throws }`
  - `public struct SquirrelPackageVerifier: PackageVerifying { static let teamID = "28HU5A7B46"; init(); static func checkPkgutil(status: Int32, output: String) throws; static func checkSpctl(status: Int32, output: String) throws }`

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct PackageVerifierTests {
    static let goodPkgutil = """
    Package "Squirrel-1.1.2.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Signed with a trusted timestamp on: 2026-01-14 01:32:48 +0000
       Certificate Chain:
        1. Developer ID Installer: Yuncao Liu (28HU5A7B46)
           Expires: 2027-02-01 22:12:15 +0000
        2. Developer ID Certification Authority
        3. Apple Root CA
    """

    @Test func 正常的包通过() throws {
        try SquirrelPackageVerifier.checkPkgutil(status: 0, output: Self.goodPkgutil)
        try SquirrelPackageVerifier.checkSpctl(status: 0, output: """
        Squirrel-1.1.2.pkg: accepted
        source=Notarized Developer ID
        origin=Developer ID Installer: Yuncao Liu (28HU5A7B46)
        """)
    }

    @Test func 包被改过() {
        #expect(throws: VerificationError.invalidPackage("Status: package is invalid (checksum did not verify)")) {
            try SquirrelPackageVerifier.checkPkgutil(status: 1, output: "Package \"bad.pkg\":\n   Status: package is invalid (checksum did not verify)\n")
        }
    }

    @Test func 别人签名的() {
        let other = Self.goodPkgutil.replacingOccurrences(of: "Yuncao Liu (28HU5A7B46)", with: "Someone Else (ABCDE12345)")
        #expect(throws: VerificationError.wrongTeam("1. Developer ID Installer: Someone Else (ABCDE12345)")) {
            try SquirrelPackageVerifier.checkPkgutil(status: 0, output: other)
        }
    }

    @Test func 没公证() {
        let output = Self.goodPkgutil.replacingOccurrences(of: "   Notarization: trusted by the Apple notary service\n", with: "")
        #expect(throws: VerificationError.notNotarized) {
            try SquirrelPackageVerifier.checkPkgutil(status: 0, output: output)
        }
    }

    @Test func 不是开发者证书签的() {
        let output = Self.goodPkgutil.replacingOccurrences(of: "signed by a developer certificate issued by Apple for distribution", with: "signed by a certificate trusted by Mac OS X")
        #expect(throws: VerificationError.notDeveloperID) {
            try SquirrelPackageVerifier.checkPkgutil(status: 0, output: output)
        }
    }

    @Test func Gatekeeper拒绝() {
        #expect(throws: VerificationError.gatekeeperRejected("junk.pkg: rejected source=no usable signature")) {
            try SquirrelPackageVerifier.checkSpctl(status: 3, output: "junk.pkg: rejected\nsource=no usable signature\n")
        }
    }

    @Test func sha256对不上() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = dir.url.appending(path: "x.pkg")
        try Data("hello".utf8).write(to: pkg)
        let actual = Hashing.sha256(of: Data("hello".utf8))
        #expect(throws: VerificationError.checksumMismatch(expected: "00", actual: actual)) {
            try SquirrelPackageVerifier().verify(pkg, sha256: "00")
        }
    }

    @Test func 错误信息是中文() {
        #expect(VerificationError.notNotarized.description == "鼠须管安装包没有经过苹果公证，不安装")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PackageVerifierTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SquirrelPackageVerifier' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Install/PackageVerifier.swift`**

```swift
import Foundation

public enum VerificationError: Error, Equatable, Sendable, CustomStringConvertible {
    case checksumMismatch(expected: String, actual: String)
    case invalidPackage(String)
    case notDeveloperID
    case notNotarized
    case wrongTeam(String?)
    case gatekeeperRejected(String)

    public var description: String {
        switch self {
        case .checksumMismatch:
            return "下载的鼠须管安装包和 GitHub 上公布的校验值不一样（可能下载坏了或被改过），不安装"
        case .invalidPackage(let detail):
            return "鼠须管安装包坏了或被改过，不安装（\(detail)）"
        case .notDeveloperID:
            return "鼠须管安装包不是用苹果签发的开发者证书签名的，不安装"
        case .notNotarized:
            return "鼠须管安装包没有经过苹果公证，不安装"
        case .wrongTeam(let found):
            return "鼠须管安装包不是鼠须管作者签名的（\(found ?? "找不到签名者")），不安装"
        case .gatekeeperRejected(let detail):
            return "系统安全检查（Gatekeeper）拒绝了鼠须管安装包，不安装（\(detail)）"
        }
    }
}

public protocol PackageVerifying: Sendable {
    func verify(_ pkg: URL, sha256: String?) throws
}

/// 鼠须管安装包的三道检查（只改了 1 个字节的包 spctl 也会说 accepted，所以三道都要）
public struct SquirrelPackageVerifier: PackageVerifying {
    public static let teamID = "28HU5A7B46"

    public init() {}

    public func verify(_ pkg: URL, sha256: String?) throws {
        if let sha256 {
            let actual = try Hashing.sha256(of: pkg)
            guard actual == sha256.lowercased() else {
                throw VerificationError.checksumMismatch(expected: sha256.lowercased(), actual: actual)
            }
        }
        let p = try Shell.run("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
        try Self.checkPkgutil(status: p.status, output: p.stdout + p.stderr)
        let s = try Shell.run("/usr/sbin/spctl", ["-a", "-vv", "-t", "install", pkg.path])
        try Self.checkSpctl(status: s.status, output: s.stdout + s.stderr)
    }

    static func checkPkgutil(status: Int32, output: String) throws {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard status == 0 else {
            throw VerificationError.invalidPackage(lines.first { $0.hasPrefix("Status:") } ?? lines.joined(separator: " "))
        }
        guard lines.contains("Status: signed by a developer certificate issued by Apple for distribution") else {
            throw VerificationError.notDeveloperID
        }
        guard lines.contains("Notarization: trusted by the Apple notary service") else {
            throw VerificationError.notNotarized
        }
        let leaf = lines.first { $0.hasPrefix("1. ") }
        guard let leaf, leaf.contains("Developer ID Installer:"), leaf.hasSuffix("(\(teamID))") else {
            throw VerificationError.wrongTeam(leaf)
        }
    }

    static func checkSpctl(status: Int32, output: String) throws {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard status == 0,
              lines.contains(where: { $0.hasSuffix(": accepted") }),
              lines.contains("source=Notarized Developer ID")
        else {
            throw VerificationError.gatekeeperRejected(lines.joined(separator: " "))
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test|Expectation failed" | head -5`
Expected: 全部通过（新增 8 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Install/PackageVerifier.swift Tests/RimeKitTests/PackageVerifierTests.swift
git commit -m "feat: 鼠须管安装包的三道检查（sha256、pkgutil、spctl）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 提权安装和 `SquirrelInstaller`

**Files:**
- Create: `Sources/RimeKit/Install/PrivilegedInstaller.swift`
- Create: `Sources/RimeKit/Install/SquirrelInstaller.swift`
- Modify: `Tests/RimeKitTests/Support/InstallFakes.swift`（加 `FakeVerifier`、`FakePrivileged`）
- Test: `Tests/RimeKitTests/SquirrelInstallerTests.swift`

**Interfaces:**
- Consumes: `SquirrelReleaseSource`、`SquirrelVersion`、`installedSquirrelVersion`（任务 2）、`PackageVerifying`（任务 3）、`ApplyLock`、`RimeLocations`（阶段 3）、`withRetry`。
- Produces:
  - `public enum InstallError: Error, Equatable, CustomStringConvertible { case cancelled, sudoUnavailable, installerFailed(String), versionMismatch(expected: String, found: String?) }`
  - `public protocol PrivilegedInstalling: Sendable { func installPackage(_ pkg: URL) async throws }`
  - `public struct SudoPackageInstaller: PrivilegedInstalling`（`sudo -n /usr/sbin/installer -pkg … -target /`，给测试机里的 rimectl 用）
  - `public struct AuthorizationPromptInstaller: PrivilegedInstalling`（`NSAppleScript` 的 `do shell script … with administrator privileges`，在主线程上运行，用户取消时 `InstallError.cancelled`；`static func appleScript(for pkg: URL) -> String`）
  - `public enum InstallOutcome: Sendable, Equatable { case alreadyInstalled(String); case installed(String, previous: String?) }`
  - `public struct SquirrelInstaller: Sendable { init(paths:locations:http:retry:verifier:privileged:); func install(force: Bool = false) async throws -> InstallOutcome }`
  - 测试辅助：`FakeVerifier`（可设错误，记录检查过的 sha256）、`FakePrivileged`（记录装过的包；可设错误；设了 `version` 时往假的 Squirrel.app 写 Info.plist）

- [ ] **Step 1: 往 `InstallFakes.swift` 末尾加**

```swift
/// 假的检查：可以设成抛错；记录收到的 sha256
final class FakeVerifier: PackageVerifying, @unchecked Sendable {
    private let lock = NSLock()
    private var checked: [String?] = []
    var error: VerificationError?

    func verify(_ pkg: URL, sha256: String?) throws {
        lock.withLock { checked.append(sha256) }
        if let error { throw error }
    }

    var checkedSHA256: [String?] { lock.withLock { checked } }
}

/// 假的提权安装：记录装过的包；设了 version 就往假的 Squirrel.app 写 Info.plist
final class FakePrivileged: PrivilegedInstalling, @unchecked Sendable {
    private let lock = NSLock()
    private let app: URL
    private var packages: [String] = []
    var version: String?
    var error: InstallError?

    init(app: URL, version: String?) {
        self.app = app
        self.version = version
    }

    var installedPackages: [String] { lock.withLock { packages } }

    func installPackage(_ pkg: URL) async throws {
        try record(pkg)
    }

    private func record(_ pkg: URL) throws {
        lock.withLock { packages.append(pkg.lastPathComponent) }
        if let error { throw error }
        if let version { try InstallFixtures.writeInfoPlist(app: app, version: version) }
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/SquirrelInstallerTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelInstallerTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let http: FakeHTTPClient
        let verifier: FakeVerifier
        let privileged: FakePrivileged

        var installer: SquirrelInstaller {
            SquirrelInstaller(paths: paths, locations: locations, http: http, retry: .immediate,
                              verifier: verifier, privileged: privileged)
        }
    }

    /// installed：测试开始时假装已经装了的版本（nil 表示没装）
    func env(latest: String = "1.1.2", installed: String? = nil) throws -> Env {
        let dir = try TempDir()
        var locations = try DeployFixtures.locations(dir)
        locations.squirrelApp = dir.url.appending(path: "Input Methods/Squirrel.app", directoryHint: .isDirectory)
        if let installed { try InstallFixtures.writeInfoPlist(app: locations.squirrelApp, version: installed) }
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: latest, digest: "abc123")))
        http.stub(InstallFixtures.pkgURL(latest), .success(Data("fake pkg".utf8)))
        return Env(dir: dir, paths: Fixtures.paths(dir), locations: locations, http: http,
                   verifier: FakeVerifier(), privileged: FakePrivileged(app: locations.squirrelApp, version: latest))
    }

    @Test func 没装时下载检查安装() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .installed("1.1.2", previous: nil))
        #expect(e.verifier.checkedSHA256 == ["abc123"])
        #expect(e.privileged.installedPackages == ["Squirrel-1.1.2.pkg"])
        let staging = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(staging.isEmpty)
    }

    @Test func 已经装了同版本就不下载() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .alreadyInstalled("1.1.2"))
        #expect(e.http.callCount(InstallFixtures.pkgURL("1.1.2")) == 0)
        #expect(e.privileged.installedPackages.isEmpty)
    }

    @Test func 装的比最新还新也不动() async throws {
        let e = try env(latest: "1.1.2", installed: "1.2.0"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .alreadyInstalled("1.2.0"))
    }

    @Test func 旧版本会升级() async throws {
        let e = try env(latest: "1.1.2", installed: "1.1.1"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .installed("1.1.2", previous: "1.1.1"))
    }

    @Test func 加force时同版本也重装() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        #expect(try await e.installer.install(force: true) == .installed("1.1.2", previous: "1.1.2"))
        #expect(e.privileged.installedPackages == ["Squirrel-1.1.2.pkg"])
    }

    @Test func 检查不过就不安装() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.verifier.error = .wrongTeam("1. Developer ID Installer: Someone (X)")
        await #expect(throws: VerificationError.wrongTeam("1. Developer ID Installer: Someone (X)")) {
            try await e.installer.install()
        }
        #expect(e.privileged.installedPackages.isEmpty)
        #expect(e.locations.installedSquirrelVersion == nil)
    }

    @Test func 用户取消授权() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.privileged.error = .cancelled
        await #expect(throws: InstallError.cancelled) { try await e.installer.install() }
        #expect(InstallError.cancelled.description == "你取消了授权，鼠须管没有安装")
    }

    @Test func 装完版本对不上() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.privileged.version = nil
        await #expect(throws: InstallError.versionMismatch(expected: "1.1.2", found: nil)) {
            try await e.installer.install()
        }
    }

    @Test func 正在应用配置时不安装() async throws {
        let e = try env(); defer { e.dir.remove() }
        let held = try ApplyLock.acquire(e.paths)
        await #expect(throws: ApplyError.busy) { try await e.installer.install() }
        _ = held
    }

    @Test func 授权框的脚本会给路径加引号() {
        let script = AuthorizationPromptInstaller.appleScript(for: URL(fileURLWithPath: "/tmp/a \"b\"/Squirrel.pkg"))
        #expect(script == #"do shell script "/usr/sbin/installer -pkg " & quoted form of "/tmp/a \"b\"/Squirrel.pkg" & " -target /" with administrator privileges"#)
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter SquirrelInstallerTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'PrivilegedInstalling' in scope`。

- [ ] **Step 4: 写 `Sources/RimeKit/Install/PrivilegedInstaller.swift`**

```swift
import Foundation

public enum InstallError: Error, Equatable, Sendable, CustomStringConvertible {
    case cancelled
    case sudoUnavailable
    case installerFailed(String)
    case versionMismatch(expected: String, found: String?)

    public var description: String {
        switch self {
        case .cancelled:
            return "你取消了授权，鼠须管没有安装"
        case .sudoUnavailable:
            return "需要管理员权限才能安装鼠须管：命令行里请先配置免密 sudo，或者加 --gui-auth 弹出系统授权框"
        case .installerFailed(let message):
            return "安装鼠须管失败：\(message)"
        case let .versionMismatch(expected, found):
            return "装完后鼠须管的版本是 \(found ?? "（找不到）")，不是预期的 \(expected)"
        }
    }
}

/// 用管理员权限运行 installer
public protocol PrivilegedInstalling: Sendable {
    func installPackage(_ pkg: URL) async throws
}

/// 免密 sudo（测试机里的 rimectl 用）
public struct SudoPackageInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL) async throws {
        let r = try Shell.run("/usr/bin/sudo", ["-n", "/usr/sbin/installer", "-pkg", pkg.path, "-target", "/"])
        guard r.status == 0 else {
            if r.stderr.contains("password is required") { throw InstallError.sudoUnavailable }
            throw InstallError.installerFailed((r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// 弹出系统授权框，用户输一次密码（应用里用；测试机里 rimectl --gui-auth 也可以用）
public struct AuthorizationPromptInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL) async throws {
        let source = Self.appleScript(for: pkg)
        try await MainActor.run {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.executeAndReturnError(&error) != nil else {
                let code = error?[NSAppleScript.errorNumber] as? Int
                if code == -128 { throw InstallError.cancelled }   // 用户点了取消
                throw InstallError.installerFailed((error?[NSAppleScript.errorMessage] as? String) ?? "未知错误 \(code ?? 0)")
            }
        }
    }

    /// 路径用 AppleScript 的 quoted form of 交给 shell，避免空格、引号出问题
    static func appleScript(for pkg: URL) -> String {
        let escaped = pkg.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return #"do shell script "/usr/sbin/installer -pkg " & quoted form of "\#(escaped)" & " -target /" with administrator privileges"#
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Install/SquirrelInstaller.swift`**

```swift
import Foundation

public enum InstallOutcome: Sendable, Equatable {
    /// 已经装了同版本或更新的版本，没动
    case alreadyInstalled(String)
    case installed(String, previous: String?)
}

/// 下载、检查、安装鼠须管（设计 6.2 第 1 步）
public struct SquirrelInstaller: Sendable {
    let paths: AppPaths
    let locations: RimeLocations
    let http: any HTTPClient
    let retry: RetryPolicy
    let verifier: any PackageVerifying
    let privileged: any PrivilegedInstalling

    public init(paths: AppPaths, locations: RimeLocations, http: any HTTPClient, retry: RetryPolicy = .standard,
                verifier: any PackageVerifying = SquirrelPackageVerifier(), privileged: any PrivilegedInstalling) {
        self.paths = paths
        self.locations = locations
        self.http = http
        self.retry = retry
        self.verifier = verifier
        self.privileged = privileged
    }

    public func install(force: Bool = false) async throws -> InstallOutcome {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let current = locations.installedSquirrelVersion
        let release = try await SquirrelReleaseSource(http: http, retry: retry).latest()
        if !force, let current, let have = SquirrelVersion(current), let latest = SquirrelVersion(release.version), have >= latest {
            return .alreadyInstalled(current)
        }

        let fm = FileManager.default
        let work = paths.staging.appending(path: "install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let pkg = work.appending(path: "Squirrel-\(release.version).pkg")
        let http = self.http
        try await withRetry(retry) { try await http.download(release.downloadURL, to: pkg) }
        try verifier.verify(pkg, sha256: release.sha256)
        try await privileged.installPackage(pkg)

        let after = locations.installedSquirrelVersion
        guard let after, let installed = SquirrelVersion(after), let expected = SquirrelVersion(release.version), installed == expected else {
            throw InstallError.versionMismatch(expected: release.version, found: after)
        }
        return .installed(after, previous: current)
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|warning:|Test run|✘ Test|Expectation failed" | head -6`
Expected: 全部通过（新增 10 个）。

- [ ] **Step 7: 提交**

```bash
git add Sources/RimeKit/Install Tests/RimeKitTests
git commit -m "feat: 下载、检查、提权安装鼠须管（系统授权框 / 免密 sudo）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 输入法状态和启用流程

**Files:**
- Create: `Sources/RimeKit/Install/InputSource.swift`
- Create: `Sources/RimeKit/Install/SquirrelActivator.swift`
- Modify: `Tests/RimeKitTests/Support/InstallFakes.swift`（加 `FakeInputSource`）
- Test: `Tests/RimeKitTests/SquirrelActivatorTests.swift`

**Interfaces:**
- Consumes: `SquirrelControlling`、`DeployWatcher`、`RimeLocations`、`ApplyError`（阶段 3）；任务 1 的结论。
- Produces:
  - `public struct InputSourceState: Sendable, Equatable { registered: Bool; enabled: Bool; selected: Bool }`
  - `public enum InputSourceError: Error, Equatable, CustomStringConvertible { case notFound, selectFailed(Int), openSettingsFailed(String) }`
  - `public protocol InputSourceControlling: Sendable { func state() -> InputSourceState; func selectSquirrel() throws; func openKeyboardSettings() throws; func pump(_ seconds: Double) async }`
  - `public struct TISInputSourceService: InputSourceControlling`（`mainID`、`hansID`、`settingsURL` 常量）
  - `public enum ActivationOutcome: Sendable, Equatable { case ready(openedSettings: Bool, launched: Bool); case timedOut; case notRegistered }`
  - `public struct SquirrelActivator: Sendable { init(locations:inputSource:squirrel:watcher:timeout:pollInterval:); func activate(onWaiting: @Sendable () -> Void = {}) async throws -> ActivationOutcome }`
  - 测试辅助 `FakeInputSource`（初始状态；`enableAfterPumps` 设了就在等了这么多次后变成已启用；记录调用）

- [ ] **Step 1: 往 `InstallFakes.swift` 末尾加**

```swift
/// 假的输入法服务
final class FakeInputSource: InputSourceControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var current: InputSourceState
    private var pumps = 0
    private var log: [String] = []
    /// 等了这么多次之后，变成用户已经添加好
    var enableAfterPumps: Int?
    var selectError: InputSourceError?

    init(_ state: InputSourceState) {
        current = state
    }

    var calls: [String] { lock.withLock { log } }
    var pumpCount: Int { lock.withLock { pumps } }

    func state() -> InputSourceState { lock.withLock { current } }

    func selectSquirrel() throws {
        try lock.withLock {
            log.append("select")
            if let selectError { throw selectError }
            current.selected = true
        }
    }

    func openKeyboardSettings() throws {
        lock.withLock { log.append("open") }
    }

    func pump(_ seconds: Double) async {
        recordPump()
    }

    private func recordPump() {
        lock.withLock {
            pumps += 1
            if let n = enableAfterPumps, pumps >= n { current.enabled = true }
        }
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/SquirrelActivatorTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct SquirrelActivatorTests {
    func make(_ dir: TempDir, _ input: FakeInputSource, running: Bool, timeout: Double = 5) throws -> (SquirrelActivator, FakeSquirrel) {
        let l = try DeployFixtures.locations(dir)
        let squirrel = FakeSquirrel(locations: l, running: running)
        let activator = SquirrelActivator(locations: l, inputSource: input, squirrel: squirrel,
                                          watcher: DeployFixtures.watcher(l), timeout: timeout, pollInterval: 1)
        return (activator, squirrel)
    }

    @Test func 用户添加后切换过去并启动鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        input.enableAfterPumps = 3
        let (activator, squirrel) = try make(dir, input, running: false)
        let waited = Flag()
        let outcome = try await activator.activate(onWaiting: { waited.set() })
        #expect(outcome == .ready(openedSettings: true, launched: true))
        #expect(input.calls == ["open", "select"])
        #expect(input.pumpCount == 3)
        #expect(waited.isSet)
        #expect(squirrel.calls == ["launch"])
    }

    @Test func 已经添加好也选中了就什么都不用做() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true))
        let (activator, squirrel) = try make(dir, input, running: true)
        #expect(try await activator.activate() == .ready(openedSettings: false, launched: false))
        #expect(input.calls.isEmpty)
        #expect(squirrel.calls.isEmpty)
    }

    @Test func 用户一直不添加就超时() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        let (activator, _) = try make(dir, input, running: false, timeout: 3)
        #expect(try await activator.activate() == .timedOut)
        #expect(input.pumpCount == 3)
        #expect(!input.calls.contains("select"))
    }

    @Test func 系统里没有注册鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: false, enabled: false, selected: false))
        let (activator, _) = try make(dir, input, running: false)
        #expect(try await activator.activate() == .notRegistered)
    }

    @Test func 没装鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        var l = try DeployFixtures.locations(dir)
        l.squirrelApp = dir.url.appending(path: "None.app")
        let input = FakeInputSource(InputSourceState(registered: false, enabled: false, selected: false))
        let activator = SquirrelActivator(locations: l, inputSource: input, squirrel: FakeSquirrel(locations: l, running: false),
                                          watcher: DeployFixtures.watcher(l), timeout: 1, pollInterval: 1)
        await #expect(throws: ApplyError.squirrelNotInstalled) { try await activator.activate() }
    }

    @Test func 切换失败要报出来() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: false))
        input.selectError = .selectFailed(-50)
        let (activator, _) = try make(dir, input, running: true)
        await #expect(throws: InputSourceError.selectFailed(-50)) { try await activator.activate() }
    }
}

/// 线程安全的「发生过没有」
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter SquirrelActivatorTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'InputSourceControlling' in scope`。

- [ ] **Step 4: 写 `Sources/RimeKit/Install/InputSource.swift`**

（下面的 `pump` 按任务 1 的结论：用 `CFRunLoopRunInMode` 让系统通知进来。如果任务 1 的结论是两种都看不到，按任务 1 Step 3 的后备办法改，并写 Ruling。）

```swift
import Carbon
import Foundation

public struct InputSourceState: Sendable, Equatable {
    /// 系统里有鼠须管的主输入源（安装时注册的）
    public var registered: Bool
    /// 用户在系统设置里添加了鼠须管（主输入源 enabled）
    public var enabled: Bool
    /// 当前选中的是鼠须管
    public var selected: Bool

    public init(registered: Bool, enabled: Bool, selected: Bool) {
        self.registered = registered
        self.enabled = enabled
        self.selected = selected
    }
}

public enum InputSourceError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound
    case selectFailed(Int)
    case openSettingsFailed(String)

    public var description: String {
        switch self {
        case .notFound: return "系统里找不到「鼠须管 - 简体」输入源"
        case .selectFailed(let code): return "切换到鼠须管失败（OSStatus \(code)），可以按输入法切换键手动切换"
        case .openSettingsFailed(let message): return "打开系统设置失败：\(message)"
        }
    }
}

/// 查看、切换输入法；等待用户操作时让系统通知进来
public protocol InputSourceControlling: Sendable {
    func state() -> InputSourceState
    func selectSquirrel() throws
    func openKeyboardSettings() throws
    func pump(_ seconds: Double) async
}

/// 用 Carbon 的 TIS 接口（要在用户的桌面会话里运行）
public struct TISInputSourceService: InputSourceControlling {
    public static let mainID = "im.rime.inputmethod.Squirrel"
    public static let hansID = "im.rime.inputmethod.Squirrel.Hans"
    public static let settingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    public init() {}

    public func state() -> InputSourceState {
        let main = Self.sources().first { Self.id($0) == Self.mainID }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return InputSourceState(
            registered: main != nil,
            enabled: main.map { Self.bool($0, kTISPropertyInputSourceIsEnabled) } ?? false,
            selected: Self.id(current).hasPrefix(Self.mainID))
    }

    public func selectSquirrel() throws {
        guard let hans = Self.sources().first(where: { Self.id($0) == Self.hansID }) else { throw InputSourceError.notFound }
        let status = TISSelectInputSource(hans)
        guard status == noErr else { throw InputSourceError.selectFailed(Int(status)) }
    }

    public func openKeyboardSettings() throws {
        let r = try Shell.run("/usr/bin/open", [Self.settingsURL])
        guard r.status == 0 else { throw InputSourceError.openSettingsFailed(r.stderr) }
    }

    /// 等待时让主线程的 run loop 转起来，系统发来的「输入源变了」通知才能更新 TIS 的缓存（任务 1 实测）
    public func pump(_ seconds: Double) async {
        await MainActor.run { _ = CFRunLoopRunInMode(.defaultMode, seconds, false) }
    }

    static func sources() -> [TISInputSource] {
        (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    static func id(_ source: TISInputSource) -> String {
        property(source, kTISPropertyInputSourceID) ?? ""
    }

    static func bool(_ source: TISInputSource, _ key: CFString) -> Bool {
        (property(source, key) as Bool?) ?? false
    }

    static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let p = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Install/SquirrelActivator.swift`**

```swift
import Foundation

public enum ActivationOutcome: Sendable, Equatable {
    /// 鼠须管可以用了。openedSettings：等过用户在系统设置里添加；launched：启动了鼠须管
    case ready(openedSettings: Bool, launched: Bool)
    /// 等到时间用户还没添加
    case timedOut
    /// 系统里没有鼠须管的输入源（安装没注册上），建议重新安装
    case notRegistered
}

/// 启用鼠须管（设计 6.2 第 1 步后半）：没添加就打开系统设置等用户添加 → 切换过去 → 没运行就启动
public struct SquirrelActivator: Sendable {
    let locations: RimeLocations
    let inputSource: any InputSourceControlling
    let squirrel: any SquirrelControlling
    let watcher: DeployWatcher
    let timeout: Double
    let pollInterval: Double

    public init(locations: RimeLocations, inputSource: any InputSourceControlling, squirrel: any SquirrelControlling,
                watcher: DeployWatcher, timeout: Double = 600, pollInterval: Double = 1) {
        self.locations = locations
        self.inputSource = inputSource
        self.squirrel = squirrel
        self.watcher = watcher
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    /// onWaiting：打开系统设置、开始等用户添加时调用一次（界面或命令行在这里告诉用户怎么做）
    public func activate(onWaiting: @Sendable () -> Void = {}) async throws -> ActivationOutcome {
        guard locations.squirrelInstalled else { throw ApplyError.squirrelNotInstalled }
        var state = inputSource.state()
        guard state.registered else { return .notRegistered }

        var opened = false
        if !state.enabled {
            try inputSource.openKeyboardSettings()
            opened = true
            onWaiting()
            var waited = 0.0
            while !state.enabled {
                if waited >= timeout { return .timedOut }
                await inputSource.pump(pollInterval)
                waited += pollInterval
                state = inputSource.state()
            }
        }
        if !state.selected { try inputSource.selectSquirrel() }

        var launched = false
        if !squirrel.isRunning() {
            let previous = watcher.lastBuildTime()
            let snapshot = watcher.snapshot()
            try squirrel.launch()
            launched = true
            _ = await watcher.wait(previousBuildTime: previous, since: snapshot)   // 等它第一次部署完，~/Library/Rime 就有了
        }
        return .ready(openedSettings: opened, launched: launched)
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|warning:|Test run|✘ Test|Expectation failed" | head -6`
Expected: 全部通过（新增 6 个）。

- [ ] **Step 7: 提交**

```bash
git add Sources/RimeKit/Install Tests/RimeKitTests
git commit -m "feat: 输入法状态（TIS）和启用流程：打开设置、等用户添加、切换、启动

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 环境检查 `Doctor`

**Files:**
- Create: `Sources/RimeKit/Install/Doctor.swift`
- Test: `Tests/RimeKitTests/DoctorTests.swift`

**Interfaces:**
- Consumes: `installedSquirrelVersion`、`SquirrelReleaseSource`、`SquirrelVersion`（任务 2）、`InputSourceControlling`（任务 5）、`SquirrelControlling`、`DeployWatcher`、`Ledger`、`SettingsStore`。
- Produces:
  - `public enum CheckLevel: String, Sendable { case ok, warning, problem }`
  - `public struct DoctorCheck: Sendable, Equatable { name: String; level: CheckLevel; message: String; hint: String? }`
  - `public struct Doctor: Sendable { init(paths:locations:inputSource:squirrel:releaseSource:); func run() async -> [DoctorCheck] }`（`releaseSource` 为空表示不联网）
  - 检查项（按顺序）：「鼠须管」「输入法」「鼠须管进程」「Rime 目录」「设置」「应用管理的配置」。没装鼠须管时只出第 1 项和「设置」。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct DoctorTests {
    func doctor(_ dir: TempDir, installed: String?, input: InputSourceState, running: Bool,
                latest: String? = nil) throws -> (Doctor, RimeLocations) {
        var l = try DeployFixtures.locations(dir)
        if installed == nil {
            l.squirrelApp = dir.url.appending(path: "None.app")
        } else {
            try InstallFixtures.writeInfoPlist(app: l.squirrelApp, version: installed!)
        }
        var source: SquirrelReleaseSource?
        if let latest {
            let http = FakeHTTPClient()
            http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: latest, digest: nil)))
            source = SquirrelReleaseSource(http: http, retry: .immediate)
        }
        let d = Doctor(paths: Fixtures.paths(dir), locations: l, inputSource: FakeInputSource(input),
                       squirrel: FakeSquirrel(locations: l, running: running), releaseSource: source)
        return (d, l)
    }

    @Test func 新电脑上什么都没有() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: nil, input: InputSourceState(registered: false, enabled: false, selected: false), running: false)
        let checks = await d.run()
        #expect(checks.map(\.name) == ["鼠须管", "设置"])
        #expect(checks[0] == DoctorCheck(name: "鼠须管", level: .problem, message: "还没有安装", hint: "运行 rimectl install"))
        #expect(checks[1].level == .warning)
    }

    @Test func 装了但还没在系统设置里添加() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: false, selected: false), running: false)
        let checks = await d.run()
        #expect(checks.first { $0.name == "输入法" } == DoctorCheck(
            name: "输入法", level: .problem, message: "还没有在系统设置里添加鼠须管", hint: "运行 rimectl activate"))
        #expect(checks.first { $0.name == "鼠须管进程" }?.level == .warning)
        #expect(checks.first { $0.name == "Rime 目录" }?.level == .warning)
    }

    @Test func 一切正常() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, l) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: true, selected: true), running: true,
                                latest: "1.1.2")
        try FakeSquirrel(locations: l, running: true).reload()   // 留下 user.yaml（部署过）
        try SettingsStore(paths: Fixtures.paths(dir)).save(.starter(.rimeIce))
        try Ledger(entries: [:], appliedAt: Date(timeIntervalSince1970: 1_000)).save(Fixtures.paths(dir))
        let checks = await d.run()
        #expect(checks.allSatisfy { $0.level == .ok }, "\(checks)")
        #expect(checks.first { $0.name == "鼠须管" }?.message == "已安装 1.1.2（是最新版）")
    }

    @Test func 有新版本时提醒但不算问题() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.1", input: InputSourceState(registered: true, enabled: true, selected: true), running: true,
                                latest: "1.1.2")
        let check = await d.run().first { $0.name == "鼠须管" }
        #expect(check?.level == .ok)
        #expect(check?.message == "已安装 1.1.1（最新是 1.1.2，鼠须管会自己提示更新）")
    }

    @Test func 添加了但没选中() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, _) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: true, selected: false), running: true)
        #expect(await d.run().first { $0.name == "输入法" }?.level == .warning)
    }

    @Test func 有外部改动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (d, l) = try doctor(dir, installed: "1.1.2", input: InputSourceState(registered: true, enabled: true, selected: true), running: true)
        try Ledger(entries: ["gone.yaml": LedgerEntry(sha256: "x", origin: "generated")], appliedAt: Date()).save(Fixtures.paths(dir))
        _ = l
        let check = await d.run().first { $0.name == "应用管理的配置" }
        #expect(check?.level == .warning)
        #expect(check?.message == "有 1 个文件在应用外被改过或删了")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DoctorTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'Doctor' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Install/Doctor.swift`**

```swift
import Foundation

public enum CheckLevel: String, Sendable {
    case ok, warning, problem
}

public struct DoctorCheck: Sendable, Equatable {
    public let name: String
    public let level: CheckLevel
    public let message: String
    /// 下一步该做什么
    public let hint: String?

    public init(name: String, level: CheckLevel, message: String, hint: String? = nil) {
        self.name = name
        self.level = level
        self.message = message
        self.hint = hint
    }
}

/// 环境检查：逐项看，告诉用户下一步做什么（设计 6.2 第 1 步）
public struct Doctor: Sendable {
    let paths: AppPaths
    let locations: RimeLocations
    let inputSource: any InputSourceControlling
    let squirrel: any SquirrelControlling
    /// 为空表示不联网查最新版本
    let releaseSource: SquirrelReleaseSource?

    public init(paths: AppPaths, locations: RimeLocations, inputSource: any InputSourceControlling,
                squirrel: any SquirrelControlling, releaseSource: SquirrelReleaseSource?) {
        self.paths = paths
        self.locations = locations
        self.inputSource = inputSource
        self.squirrel = squirrel
        self.releaseSource = releaseSource
    }

    public func run() async -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        guard let version = locations.installedSquirrelVersion, locations.squirrelInstalled else {
            checks.append(DoctorCheck(name: "鼠须管", level: .problem, message: "还没有安装", hint: "运行 rimectl install"))
            checks.append(settingsCheck())
            return checks
        }
        checks.append(await squirrelCheck(version))
        checks.append(inputCheck())
        checks.append(squirrel.isRunning()
            ? DoctorCheck(name: "鼠须管进程", level: .ok, message: "正在运行")
            : DoctorCheck(name: "鼠须管进程", level: .warning, message: "没在运行", hint: "运行 rimectl activate"))
        checks.append(rimeDirectoryCheck())
        checks.append(settingsCheck())
        checks.append(managedCheck())
        return checks
    }

    private func squirrelCheck(_ version: String) async -> DoctorCheck {
        guard let releaseSource else {
            return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)")
        }
        do {
            let latest = try await releaseSource.latest().version
            if let have = SquirrelVersion(version), let newest = SquirrelVersion(latest), have < newest {
                return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)（最新是 \(latest)，鼠须管会自己提示更新）")
            }
            return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)（是最新版）")
        } catch {
            return DoctorCheck(name: "鼠须管", level: .ok, message: "已安装 \(version)（查不到最新版本：\(error)）")
        }
    }

    private func inputCheck() -> DoctorCheck {
        let s = inputSource.state()
        if !s.registered {
            return DoctorCheck(name: "输入法", level: .problem, message: "系统里没有鼠须管的输入源", hint: "运行 rimectl install --force 重新安装")
        }
        if !s.enabled {
            return DoctorCheck(name: "输入法", level: .problem, message: "还没有在系统设置里添加鼠须管", hint: "运行 rimectl activate")
        }
        if !s.selected {
            return DoctorCheck(name: "输入法", level: .warning, message: "已添加，但现在选中的不是鼠须管", hint: "运行 rimectl activate，或按输入法切换键")
        }
        return DoctorCheck(name: "输入法", level: .ok, message: "已添加并选中鼠须管")
    }

    private func rimeDirectoryCheck() -> DoctorCheck {
        let watcher = DeployWatcher(locations: locations)
        guard let time = watcher.lastBuildTime() else {
            return DoctorCheck(name: "Rime 目录", level: .warning, message: "鼠须管还没部署过", hint: "运行 rimectl activate")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(time)).formatted(date: .numeric, time: .shortened)
        return DoctorCheck(name: "Rime 目录", level: .ok, message: "上次部署：\(date)")
    }

    private func settingsCheck() -> DoctorCheck {
        let exists = (try? SettingsStore(paths: paths).load()) != nil
        return exists
            ? DoctorCheck(name: "设置", level: .ok, message: "已有设置")
            : DoctorCheck(name: "设置", level: .warning, message: "还没有设置", hint: "运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
    }

    private func managedCheck() -> DoctorCheck {
        guard let ledger = try? Ledger.load(paths), ledger.appliedAt != nil else {
            return DoctorCheck(name: "应用管理的配置", level: .warning, message: "还没应用过设置", hint: "运行 rimectl apply")
        }
        let changes = ledger.externalChanges(in: locations.rimeDirectory)
        if changes.isEmpty {
            return DoctorCheck(name: "应用管理的配置", level: .ok, message: "\(ledger.entries.count) 个文件，没有外部改动")
        }
        return DoctorCheck(name: "应用管理的配置", level: .warning, message: "有 \(changes.count) 个文件在应用外被改过或删了",
                           hint: "运行 rimectl status 看是哪些；rimectl apply 会先问你")
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|warning:|Test run|✘ Test|Expectation failed" | head -6`
Expected: 全部通过（新增 6 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Install/Doctor.swift Tests/RimeKitTests/DoctorTests.swift
git commit -m "feat: 环境检查 Doctor：逐项检查并给出下一步

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `rimectl install`、`activate`、`doctor`

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`
- Test: `Tests/RimeKitTests/RimectlInstallTests.swift`

**Interfaces:**
- Consumes: `SquirrelInstaller`、`SudoPackageInstaller`、`AuthorizationPromptInstaller`、`SquirrelPackageVerifier`、`SquirrelActivator`、`TISInputSourceService`、`Doctor`、`SquirrelReleaseSource`。
- Produces:
  - `Rimectl.Context` 加字段（带默认值）：`var inputSource: (any InputSourceControlling)? = nil`、`var privileged: (any PrivilegedInstalling)? = nil`、`var verifier: (any PackageVerifying)? = nil`、`var activationTimeout: Double = 600`
  - 新参数：`--gui-auth`、`--offline`、`--timeout 秒`（`--force` 已有）
  - 命令：`rimectl install [--force] [--gui-auth]`、`rimectl activate [--timeout 秒]`、`rimectl doctor [--offline]`
  - 退出码：`install` 成功或已是最新 0，取消或出错 1；`activate` 就绪 0，超时或没注册 1；`doctor` 没有「问题」级别 0，有 1。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlInstallTests {
    struct Env {
        let dir: TempDir
        let locations: RimeLocations
        let input: FakeInputSource
        let privileged: FakePrivileged
        let output: Output
        let context: Rimectl.Context
        func run(_ args: [String]) async -> Int32 { await Rimectl.run(args, context) }
    }

    func env(installed: String? = nil, input: InputSourceState = InputSourceState(registered: true, enabled: false, selected: false)) throws -> Env {
        let dir = try TempDir()
        // 用 DeployFixtures 的假鼠须管（带 rime_deployer，activate 才认为装了）；没写 Info.plist 时版本为空，算没装
        let locations = try DeployFixtures.locations(dir)
        if let installed { try InstallFixtures.writeInfoPlist(app: locations.squirrelApp, version: installed) }
        let http = FakeHTTPClient()
        http.stub(SquirrelReleaseSource.latestURL, .success(InstallFixtures.releaseJSON(version: "1.1.2", digest: "abc")))
        http.stub(InstallFixtures.pkgURL("1.1.2"), .success(Data("pkg".utf8)))
        let fakeInput = FakeInputSource(input)
        let privileged = FakePrivileged(app: locations.squirrelApp, version: "1.1.2")
        let output = Output(echo: false)
        let catalog = try Catalog.builtIn()
        let context = Rimectl.Context(
            http: http, retry: .immediate, catalog: { catalog }, defaultPaths: Fixtures.paths(dir), output: output,
            locations: locations, compiler: FakeCompiler(), squirrel: FakeSquirrel(locations: locations, running: false),
            deployTimeout: .milliseconds(20), sleep: { _ in },
            inputSource: fakeInput, privileged: privileged, verifier: FakeVerifier(), activationTimeout: 3)
        return Env(dir: dir, locations: locations, input: fakeInput, privileged: privileged, output: output, context: context)
    }

    @Test func install装上() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["install"]) == 0)
        #expect(e.output.text.contains("已安装鼠须管 1.1.2"))
        #expect(await e.run(["install"]) == 0)
        #expect(e.output.text.contains("已经装了鼠须管 1.1.2"))
    }

    @Test func install被取消() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.privileged.error = .cancelled
        #expect(await e.run(["install"]) == 1)
        #expect(e.output.text.contains("你取消了授权"))
    }

    @Test func activate等用户添加() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        e.input.enableAfterPumps = 2
        #expect(await e.run(["activate"]) == 0)
        #expect(e.output.text.contains("已打开系统设置的键盘页"))
        #expect(e.output.text.contains("鼠须管可以用了"))
    }

    @Test func activate超时() async throws {
        let e = try env(installed: "1.1.2"); defer { e.dir.remove() }
        #expect(await e.run(["activate", "--timeout", "2"]) == 1)
        #expect(e.output.text.contains("还没看到鼠须管被添加"))
    }

    @Test func doctor() async throws {
        let e = try env(installed: nil); defer { e.dir.remove() }
        #expect(await e.run(["doctor", "--offline"]) == 1)
        #expect(e.output.text.contains("[问题] 鼠须管：还没有安装"))
        #expect(e.output.text.contains("→ 运行 rimectl install"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RimectlInstallTests 2>&1 | grep -E "error:" | head -3`
Expected: `extra arguments … in call`（`Context` 还没有新字段）。

- [ ] **Step 3: 改 `Sources/rimectl/Rimectl.swift`**

`Context` 里 `var sleep: …` 后面加：

```swift
        /// 空就用真的 TIS
        var inputSource: (any InputSourceControlling)? = nil
        /// 空就按 --gui-auth 选系统授权框或免密 sudo
        var privileged: (any PrivilegedInstalling)? = nil
        /// 空就用真的三道检查
        var verifier: (any PackageVerifying)? = nil
        var activationTimeout: Double = 600
```

`usage` 里 `rimectl restore …` 那行后面加三行：

```swift
      rimectl install [--force] [--gui-auth]                   下载、检查、安装鼠须管（--gui-auth 弹系统授权框，否则用免密 sudo）
      rimectl activate [--timeout 秒]                           打开系统设置等你添加鼠须管，然后切换过去并启动它
      rimectl doctor [--offline]                               检查环境，告诉你下一步做什么
```

参数解析：在 `var listOnly = false` 后面加

```swift
        var guiAuth = false
        var offline = false
        var timeout: Double?
```

在 `case "--list":` 前面加

```swift
            case "--gui-auth":
                guiAuth = true
                i += 1
            case "--offline":
                offline = true
                i += 1
            case "--timeout":
                guard i + 1 < args.count, let seconds = Double(args[i + 1]) else { out.error(usage); return 2 }
                timeout = seconds
                i += 2
```

`switch command` 里加（放在 `case "fetch":` 前面）：

```swift
            case "install":
                return try await install(force: force, guiAuth: guiAuth, paths: paths, locations: locations, context)
            case "activate":
                return try await activate(timeout: timeout ?? context.activationTimeout, locations: locations, context)
            case "doctor":
                return await doctor(offline: offline, paths: paths, locations: locations, context)
```

加这三个函数（放在 `report` 前面）：

```swift
    private static func install(force: Bool, guiAuth: Bool, paths: AppPaths, locations: RimeLocations,
                                _ context: Context) async throws -> Int32 {
        let out = context.output
        let privileged: any PrivilegedInstalling = context.privileged
            ?? (guiAuth ? AuthorizationPromptInstaller() : SudoPackageInstaller())
        let installer = SquirrelInstaller(paths: paths, locations: locations, http: context.http, retry: context.retry,
                                          verifier: context.verifier ?? SquirrelPackageVerifier(), privileged: privileged)
        out.line("正在检查鼠须管的最新版本……")
        switch try await installer.install(force: force) {
        case .alreadyInstalled(let version):
            out.line("已经装了鼠须管 \(version)，是最新的，不用装")
        case let .installed(version, previous):
            out.line(previous.map { "已安装鼠须管 \(version)（原来是 \($0)）" } ?? "已安装鼠须管 \(version)")
            out.line("下一步：运行 rimectl activate，在系统设置里添加鼠须管")
        }
        return 0
    }

    private static func activate(timeout: Double, locations: RimeLocations, _ context: Context) async throws -> Int32 {
        let out = context.output
        let activator = SquirrelActivator(
            locations: locations,
            inputSource: context.inputSource ?? TISInputSourceService(),
            squirrel: context.squirrel ?? SquirrelControl(locations: locations),
            watcher: DeployWatcher(locations: locations, timeout: context.deployTimeout, sleep: context.sleep),
            timeout: timeout)
        let outcome = try await activator.activate(onWaiting: {
            out.line("已打开系统设置的键盘页。请在「文字输入 → 输入法 → 编辑… → + → 简体中文 → 鼠须管」里添加，")
            out.line("添加好后这里会自动继续（最多等 \(Int(timeout)) 秒）……")
        })
        switch outcome {
        case let .ready(_, launched):
            if launched { out.line("已启动鼠须管") }
            out.line("鼠须管可以用了")
            return 0
        case .timedOut:
            out.error("等了 \(Int(timeout)) 秒，还没看到鼠须管被添加。添加好后再运行一次 rimectl activate")
            return 1
        case .notRegistered:
            out.error("系统里没有鼠须管的输入源，可能没装好。请运行 rimectl install --force 重新安装")
            return 1
        }
    }

    private static func doctor(offline: Bool, paths: AppPaths, locations: RimeLocations, _ context: Context) async -> Int32 {
        let out = context.output
        let doctor = Doctor(
            paths: paths, locations: locations,
            inputSource: context.inputSource ?? TISInputSourceService(),
            squirrel: context.squirrel ?? SquirrelControl(locations: locations),
            releaseSource: offline ? nil : SquirrelReleaseSource(http: context.http, retry: context.retry))
        let checks = await doctor.run()
        for check in checks {
            let mark = switch check.level {
            case .ok: "[正常]"
            case .warning: "[注意]"
            case .problem: "[问题]"
            }
            out.line("\(mark) \(check.name)：\(check.message)")
            if let hint = check.hint { out.line("       → \(hint)") }
        }
        return checks.contains { $0.level == .problem } ? 1 : 0
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|warning:|Test run|✘ Test|Expectation failed" | head -6`
Expected: 全部通过（新增 5 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/rimectl Tests/RimeKitTests/RimectlInstallTests.swift
git commit -m "feat: rimectl install / activate / doctor

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 联网检查真实安装包；在干净的测试机里走一遍新电脑流程

**Files:**
- Create: `Tests/RimeKitTests/OnlineInstallerTests.swift`
- Modify: `docs/phase4-vm-log.md`

- [ ] **Step 1: 写联网测试（宿主机只下载、只检查，不安装）**

```swift
import Foundation
import Testing
@testable import RimeKit

/// 真的从 GitHub 取鼠须管安装包，做三道检查；再改 1 个字节，确认检查不过。只下载到临时目录，不安装。
/// RIMEKIT_ONLINE=1 swift test --filter OnlineInstallerTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1"))
struct OnlineInstallerTests {
    @Test func 真实安装包能通过检查改过的不能() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let release = try await SquirrelReleaseSource(http: URLSessionHTTPClient()).latest()
        #expect(release.sha256 != nil)
        let pkg = dir.url.appending(path: "Squirrel.pkg")
        try await URLSessionHTTPClient().download(release.downloadURL, to: pkg)
        try SquirrelPackageVerifier().verify(pkg, sha256: release.sha256)

        var bytes = try Data(contentsOf: pkg)
        bytes[1_000_000] ^= 0xFF
        let bad = dir.url.appending(path: "bad.pkg")
        try bytes.write(to: bad)
        #expect(throws: VerificationError.self) { try SquirrelPackageVerifier().verify(bad, sha256: release.sha256) }
        #expect(throws: VerificationError.self) { try SquirrelPackageVerifier().verify(bad, sha256: nil) }   // 不靠 sha256，pkgutil 也能发现
    }
}
```

Run: `RIMEKIT_ONLINE=1 swift test --filter OnlineInstallerTests 2>&1 | grep -E "error:|Test run|Expectation failed" | head -5`
Expected: 通过。提交：

```bash
git add Tests/RimeKitTests/OnlineInstallerTests.swift
git commit -m "test: 联网检查真实的鼠须管安装包，改过的包检查不过

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: 克隆一台干净的测试机，请用户登录桌面**

```bash
swift build 2>&1 | tail -1
./tools/vm/vm.sh new squirrel-fresh
```

请用户在 `squirrel-fresh` 的窗口里登录 `tester` 的桌面，好了告诉我。下面的命令都用这个函数在桌面会话里跑（数据目录 `/tmp/rk`）：

```bash
fresh() { ./tools/vm/vm.sh ssh squirrel-fresh "sudo launchctl asuser \$(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' $* --data-dir /tmp/rk"; }
```

- [ ] **Step 3: 环境检查 → 用系统授权框安装（用户输密码）**

```bash
fresh doctor; echo "exit=$?"
```

Expected：`[问题] 鼠须管：还没有安装` → `运行 rimectl install`，`exit=1`。

先告诉用户「测试机窗口里马上会弹出授权框，第一次请点『取消』，我确认取消能被正确处理；第二次请输入 tester 的密码」，然后：

```bash
fresh install --gui-auth; echo "exit=$?"
fresh install --gui-auth; echo "exit=$?"
fresh doctor; echo "exit=$?"
```

Expected：第一次输出「你取消了授权，鼠须管没有安装」，`exit=1`，`/Library/Input Methods` 里没有鼠须管；第二次「已安装鼠须管 1.1.2」，`exit=0`；`doctor` 显示「已安装 1.1.2（是最新版）」和「[问题] 输入法：还没有在系统设置里添加鼠须管」。

- [ ] **Step 4: 启用：用户在系统设置里添加**

告诉用户「测试机里会打开系统设置的键盘页，请按提示添加鼠须管」，然后（后台运行，最多等 600 秒）：

```bash
fresh activate; echo "exit=$?"
```

Expected：先输出「已打开系统设置的键盘页……添加好后这里会自动继续」；用户添加后几秒内输出「已启动鼠须管」「鼠须管可以用了」，`exit=0`。这一步同时验证了 Review Focus 4（同一个进程里能看到用户的添加）。然后：

```bash
fresh doctor; echo "exit=$?"
```

Expected：鼠须管、输入法、鼠须管进程、Rime 目录都是 `[正常]`；设置、应用管理的配置是 `[注意]`；`exit=0`。

- [ ] **Step 5: 接着应用起步设置，确认能打字**

```bash
fresh settings init wubi-pinyin
fresh apply; echo "exit=$?"
```

如果 `apply` 列出「不是应用写的」文件（鼠须管第一次启动时生成的默认文件），就再跑 `fresh apply --overwrite`。Expected：「部署完成」，`exit=0`。打字检查（副本）：

```bash
./tools/vm/vm.sh ssh squirrel-fresh 'rm -rf /tmp/rimecopy && rsync -a --exclude "*.userdb" ~/Library/Rime/ /tmp/rimecopy/ && "/Volumes/My Shared Files/vm/rime-type-probe" /tmp/rimecopy wubi86_jidian_pinyin g weixin qukuailian 2>/dev/null'
```

Expected：一、微信、区块链。再请用户在测试机「文本编辑」里打 `weixin`，确认出「微信」。

- [ ] **Step 6: 用免密 sudo 重装（另一条提权路径）**

```bash
fresh install; echo "exit=$?"
fresh install --force; echo "exit=$?"
fresh doctor; echo "exit=$?"
```

Expected：第一次「已经装了鼠须管 1.1.2，是最新的」；`--force` 时「已安装鼠须管 1.1.2（原来是 1.1.2）」（走免密 sudo，不弹框）；`doctor` 仍然是输入法已添加。

- [ ] **Step 7: 记录、删掉测试机**

在 `docs/phase4-vm-log.md` 里接着写「实测 2：干净测试机的新电脑流程」，按 Step 3–6 写命令、关键输出、是否符合预期。然后：

```bash
./tools/vm/vm.sh rm squirrel-fresh
git add docs/phase4-vm-log.md
git commit -m "docs: 阶段 4 测试机实测记录（新电脑流程）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 更新文档

**Files:**
- Modify: `docs/verified-facts.md`、`docs/install-test-log.md`、`docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`、`docs/superpowers/plans/2026-10-15-roadmap.md`、`CLAUDE.md`、`README.md`

- [ ] **Step 1: `verified-facts.md`**

第 1 节「安装包」表格末尾加：

```markdown
| GitHub 接口 `repos/rime/squirrel/releases/latest` 的附件带 `digest`（`sha256:…`），可以用来核对下载的安装包 | 查看（2026-10-15） |
| 已安装的版本在 `Squirrel.app/Contents/Info.plist` 的 `CFBundleVersion`（1.1.2 没有 `CFBundleShortVersionString`） | 实测（宿主机） |
| **安装包改了 1 个字节，`spctl -a -t install` 仍然 `accepted`**；`pkgutil --check-signature` 报 `package is invalid (checksum did not verify)`，退出码 1。所以要 sha256 + `pkgutil` + `spctl` 三道检查 | 实测（宿主机临时目录，2026-10-15） |
```

再按任务 1、8 的实测结果加：同一进程里能否看到输入法添加（哪种等法看得到）；`osascript`/`NSAppleScript` 授权框点「取消」时的错误号（-128）；免密 sudo 安装的结果。

- [ ] **Step 2: `install-test-log.md` 的「还没测的」**

「已经装过旧版鼠须管的电脑上升级」那条后面注明：「`rimectl install` 会在已装版本比最新旧时升级（阶段 4 用假数据测过；真机升级没测，鼠须管自带 Sparkle 也会自己升级）」。

- [ ] **Step 3: 设计文档**

- 第 3 节「两个技术细节」里「管理员权限」一条后面加：「安装前三道检查：sha256 等于 GitHub 接口的 `digest`、`pkgutil` 签名和公证且团队 ID 是 `28HU5A7B46`、`spctl` 通过（只靠 `spctl` 不够，已实测）。已经装了同版本或更新版本就不重装。」
- 6.2 第 1 步末尾加：「等待用户添加时每秒查一次，等待期间让 run loop 转起来（同一个进程里才能看到变化，阶段 4 实测）；最多等 10 分钟，超时就提示用户添加好后再点一次。」
- 第 10 节表格第 1、2 行的结论列各补一句「阶段 4 已在干净测试机里用 `rimectl install/activate` 跑通」。

- [ ] **Step 4: 路线图、CLAUDE.md、README**

- 路线图阶段 4 那一行「成果」末尾加「（已完成，2026-10-15）」。
- `CLAUDE.md` 开头阶段说明改成「阶段 0–4 已完成（…；安装鼠须管、启用、环境检查），下一步写阶段 5 的计划」。
- `README.md` 阶段说明改成「阶段 0–4 已完成（方案清单、下载缓存、生成配置、写入和部署、安装和环境检查）。下一步是阶段 5（接管已有配置）」；「开发」一节加：「- 安装、启用鼠须管只在测试机里试：`rimectl install --gui-auth`、`rimectl activate`、`rimectl doctor`」。

- [ ] **Step 5: 跑全部测试，提交，推送**

Run: `swift test 2>&1 | grep -E "error:|Test run" | tail -2`
Expected: 全部通过。

```bash
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 4 的事实和设计细节（三道检查、启用时的等待）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```
