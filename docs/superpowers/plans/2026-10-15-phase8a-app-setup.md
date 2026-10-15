# 阶段 8a：应用骨架和第一次打开的引导 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 有一个能双击打开的 macOS 应用。第一次打开时一步步带用户走完：
1. 安装鼠须管（弹系统授权框）。
2. 在系统设置里添加输入法（自动检测）。
3. 看 `~/Library/Rime`：
   - 空的 → 选起步方案；
   - 有已有配置 → 预览接管；
   - 用户有导出文件 → 从文件导入。
4. 显示「设置好了」（设计 6.2）。

主窗口的各个页面（方案、外观、文本替换、导入导出、备份、诊断）是阶段 8b。

**Architecture:** 三个新目标：
- `AppCore`：界面用的逻辑，不含 SwiftUI。
  - `AppEnvironment`：所有外部依赖集中在一起，测试时换成假的。
  - `SetupFlow`：`@Observable` 的引导状态机，只调用 RimeKit。
  - `AppInputSource`：等待时不嵌套转 run loop。
- `AppUI`：SwiftUI 视图。
- `SquirrelMacOSApp`：`@main`。

RimeKit 只加一样：`OsascriptPrivilegedInstaller`，用 `osascript` 子进程弹授权框，不在主线程里跑 `NSAppleScript`，不卡界面。

`.app` 用脚本把 SwiftPM 编出来的程序、RimeKit 的资源包和 `Info.plist` 拼起来，本机临时签名。逻辑在宿主机用假依赖测；界面在测试机里由用户点一遍。

**Tech Stack:** Swift 6.4、SwiftUI、Observation、Swift Testing、`/usr/bin/osascript`、`codesign`（临时签名）。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 2、3 节，6.1，6.2，6.4，7，8.3，11）；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## 写计划前的实测（2026-10-15，宿主机临时目录）

- 用 SwiftPM 编一个 SwiftUI `@main` 应用。手工拼成 `.app`：`Contents/MacOS/<程序>`、`Contents/Resources/<包名>_<库名>.bundle`、`Contents/Info.plist`。用 `codesign -s -` 临时签名后能启动。
- 库里的资源（`Bundle.module`）能从 `Contents/Resources/` 里找到。把编译目录里的资源包挪走以后，照样能读到，说明不依赖编译目录。

## 已经和你确认的

- 阶段 8 拆成 8a（骨架 + 第一次打开的引导）、8b（主窗口各页）。
- 主窗口里改设置后，点「应用改动」才写进鼠须管（8b 做）。

## 本阶段要定的事（计划里的做法，请确认）

| # | 问题 | 计划里的做法 | 理由 |
|---|---|---|---|
| 1 | 怎么打包成 `.app` | 不建 Xcode 工程。SwiftPM 加可执行目标 `SquirrelMacOSApp`。`tools/app/build-app.sh` 编译并拼出 `.build/app/squirrel-macos.app`（临时签名）。正式签名、公证留到发布前（设计第 11 节） | 不多一套工程文件；实测可行 |
| 2 | 应用的名字、标识 | 开发期间显示名 `squirrel-macos`，Bundle ID `io.github.pokoblin.squirrel-macos`，版本 0.1.0 | 设计第 11 节：正式名称以后定 |
| 3 | 弹授权框 | 新增 `OsascriptPrivilegedInstaller`：用 `osascript` 子进程执行和以前一样的脚本（提权后在 root 目录里重新核对再装） | 阶段 4 的待改进项：`NSAppleScript` 在主线程跑会卡住界面 |
| 4 | 等用户添加输入法时 | 应用里用 `AppInputSource`：TIS 调用照旧（在主线程），等待时只 `Task.sleep`，不再嵌套转 run loop | 阶段 4 的待改进项：应用的主 run loop 本来就在转，通知会自己进来 |
| 5 | 起步方案、接管、导入写配置时遇到 Rime 目录里应用不管的同名文件 | 都覆盖（先完整备份；第一次的这份永久保留）。接管时用户已经在预览里看过 | 和 `rimectl takeover --confirm`、`import` 一致 |
| 6 | 已经有 `settings.json` 但 Rime 目录还没由应用管理 | 当成没设置过，照常走引导；接管用 `force` | 只有 `settings init` 没 `apply` 的情况，用户在引导里已经确认 |
| 7 | 读不了文本替换时 | 接管预览照常显示，但「接管」按钮不能点，说明原因（和阶段 5 的命令行一致）；起步方案、导入不受影响（导入时只是这次不带文本替换） | 不把文本替换的内容存成手动短语 |
| 8 | 下载上游包失败 | 本地有旧版本缓存就先用旧的，没有就报错、可以重试 | 设计第 7 节；问「要不要用旧版」放到 8b |
| 9 | 重新注册输入源后 | 显示「请退出应用再打开」（同一个进程里 TIS 的「已启用」状态不会更新，阶段 4 后续实测） | 和 `rimectl activate` 的处理一致 |
| 10 | 已经由应用管理（有设置、ledger 不空） | 引导直接显示「已经设置好了」，主窗口在 8b 接上 | |
| 11 | 宿主机上运行应用 | **不在宿主机上运行**（它会读真实的 `~/Library/Rime`，点按钮还会写）；只编译、跑单元测试。界面检查都在测试机里 | 项目约定 |

## Global Constraints

- 宿主机**不碰** `~/Library/Rime`、`/Library/Input Methods`、输入法启用状态：**不在宿主机上运行应用**，只编译和跑单元测试（只用临时目录、假依赖）。
- 应用只调用 RimeKit；所有逻辑放在 `AppCore`（可测），视图里不写逻辑。
- 真实配置只在 6.1 的写入一步才改；编译失败、出错时什么都不保存（复用 `Deployer`、`TakeoverApplier`、`Importer`）。
- 隐私：界面只显示设置、文件名和条数，不显示个人词库、短语、文本替换、输入习惯的内容。
- 第三方依赖只有 Yams；不加 Xcode 工程。
- 测试机：新克隆的 `squirrel-app` 走从零开始的流程，测完删掉；`squirrel-dev` 用来测接管和导入；同时最多两台。登录桌面、输入授权密码、添加输入法、在应用里点按钮、看界面由用户做。测试机里运行宿主机编出来的程序前，先复制到测试机本地（共享文件夹只读，原地重编后直接运行可能被杀）。
- 用简单直白的中文写界面文字和错误信息。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 用户在授权框点「取消」、等添加输入法超时、下载失败、编译失败 → 引导停在一个能看懂、能重试的状态，真实配置不动（任务 2、4 有测试，任务 7 实测取消）。
2. 已有配置的电脑上打开应用 → 先预览、用户点了才接管；读不了文本替换时不能接管（任务 4 有测试，任务 7 实测）。
3. 引导的每一步在界面上都有明确的下一步，长操作有「正在做什么」的提示，界面不卡（任务 5，任务 7 由用户看）。
4. 应用打包后在另一台 Mac（测试机）上能启动，能找到方案清单（任务 1、6，任务 7 实测）。
5. 重新打开已经设置好的应用 → 不再重复引导（任务 4 有测试）。

---

## 文件结构

```
Package.swift                                   # 加 AppCore、AppUI、SquirrelMacOSApp；测试目标依赖 AppCore
Sources/RimeKit/Install/PrivilegedInstaller.swift   # OsascriptPrivilegedInstaller
Sources/AppCore/AppEnvironment.swift            # 外部依赖；live()
Sources/AppCore/AppInputSource.swift            # 等待时只 sleep 的输入法服务
Sources/AppCore/TakeoverSummary.swift           # 接管预览给界面看的摘要
Sources/AppCore/SetupFlow.swift                 # 引导状态机
Sources/AppUI/RootView.swift                    # 引导各步的视图
Sources/AppUI/TakeoverPreviewView.swift
Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift # @main
tools/app/Info.plist
tools/app/build-app.sh
Tests/RimeKitTests/
  OsascriptInstallerTests.swift
  SetupFlowTests.swift
  Support/AppFakes.swift
docs/phase8a-vm-log.md
```

---

### Task 1: 新目标和打包脚本

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AppCore/AppCore.swift`（占位，任务 3 换掉）、`Sources/AppUI/RootView.swift`（占位，任务 5 换掉）、`Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`
- Create: `tools/app/Info.plist`、`tools/app/build-app.sh`

**Interfaces:**
- Produces:
  - SwiftPM 目标：`AppCore`（依赖 RimeKit）、`AppUI`（依赖 AppCore）、可执行目标 `SquirrelMacOSApp`（依赖 AppUI）、product `.executable(name: "SquirrelMacOSApp")`；`RimeKitTests` 加依赖 `AppCore`
  - `./tools/app/build-app.sh` → 输出 `.build/app/squirrel-macos.app` 的路径

- [ ] **Step 1: 改 Package.swift**

`products` 里加 `.executable(name: "SquirrelMacOSApp", targets: ["SquirrelMacOSApp"]),`；`targets` 改成：

```swift
    targets: [
        .target(
            name: "RimeKit",
            dependencies: [.product(name: "Yams", package: "Yams")],
            resources: [.copy("Resources/catalog.json")]
        ),
        .executableTarget(name: "rimectl", dependencies: ["RimeKit"]),
        // 应用：AppCore 是界面用的逻辑（可测，不含 SwiftUI），AppUI 是视图，SquirrelMacOSApp 只有 @main
        .target(name: "AppCore", dependencies: ["RimeKit"]),
        .target(name: "AppUI", dependencies: ["AppCore"]),
        .executableTarget(name: "SquirrelMacOSApp", dependencies: ["AppUI"]),
        .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "rimectl", "AppCore"]),
    ]
```

- [ ] **Step 2: 占位源文件**

`Sources/AppCore/AppCore.swift`：

```swift
import RimeKit

/// 应用用的逻辑（任务 3 起填充）
public enum AppCore {}
```

`Sources/AppUI/RootView.swift`：

```swift
import AppCore
import SwiftUI

/// 应用的根视图（任务 5 换成引导）
public struct RootView: View {
    public init() {}

    public var body: some View {
        Text("squirrel-macos")
            .padding(40)
    }
}
```

`Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`：

```swift
import AppUI
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    var body: some Scene {
        WindowGroup("squirrel-macos") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 3: 打包脚本**

`tools/app/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SquirrelMacOSApp</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.pokoblin.squirrel-macos</string>
    <key>CFBundleName</key>
    <string>squirrel-macos</string>
    <key>CFBundleDisplayName</key>
    <string>squirrel-macos</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

`tools/app/build-app.sh`（`chmod +x`）：

```bash
#!/bin/bash
# 编译应用并拼成 .build/app/squirrel-macos.app（本机临时签名，只给测试机用）。
# 不要在宿主机上运行这个应用：它会读写真实的 ~/Library/Rime。
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --product SquirrelMacOSApp >&2
BIN="$(swift build --show-bin-path)"
APP=".build/app/squirrel-macos.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SquirrelMacOSApp" "$APP/Contents/MacOS/"
# RimeKit 的资源包（方案清单）：Bundle.module 会在 Contents/Resources 里找
cp -R "$BIN/SquirrelMacOS_RimeKit.bundle" "$APP/Contents/Resources/"
cp tools/app/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >&2
echo "$APP"
```

- [ ] **Step 4: 编译、打包、检查**

Run:
```bash
swift build 2>&1 | grep -E "error:|warning:|Compiling|Build complete" | tail -2
./tools/app/build-app.sh
codesign -v .build/app/squirrel-macos.app && echo 签名正常
ls .build/app/squirrel-macos.app/Contents/MacOS .build/app/squirrel-macos.app/Contents/Resources
swift test 2>&1 | grep -E "error:|Test run" | tail -2
```
Expected：编译通过，没有 warning；打出 `.build/app/squirrel-macos.app`；签名正常；里面有 `SquirrelMacOSApp` 和 `SquirrelMacOS_RimeKit.bundle`；测试全部通过。**不要在宿主机上 `open` 这个应用。**

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources/AppCore Sources/AppUI Sources/SquirrelMacOSApp tools/app
git commit -m "feat: 应用的目标（AppCore、AppUI、SquirrelMacOSApp）和打包脚本

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 用 osascript 子进程弹授权框

**Files:**
- Modify: `Sources/RimeKit/Install/PrivilegedInstaller.swift`
- Test: `Tests/RimeKitTests/OsascriptInstallerTests.swift`

**Interfaces:**
- Consumes: `AuthorizationPromptInstaller.appleScript(for:sha256:)`、`PrivilegedInstallScript.error(status:message:)`（阶段 4）
- Produces: `public struct OsascriptPrivilegedInstaller: PrivilegedInstalling`；`static func error(stderr: String) -> InstallError`（-128 → `.cancelled`；其它错误号交给 `PrivilegedInstallScript.error`；认不出 → `.installerFailed`）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/OsascriptInstallerTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct OsascriptInstallerTests {
    @Test func 用户点了取消() {
        #expect(OsascriptPrivilegedInstaller.error(stderr: "0:139: execution error: User canceled. (-128)\n") == .cancelled)
    }

    @Test func 脚本的退出码翻译成中文错误() {
        #expect(OsascriptPrivilegedInstaller.error(stderr: "0:300: execution error:  (90)")
                == PrivilegedInstallScript.error(status: PrivilegedInstallScript.checksumMismatch, message: ""))
        #expect(OsascriptPrivilegedInstaller.error(stderr: "0:300: execution error: installer: boom (1)")
                == .installerFailed("0:300: execution error: installer: boom (1)"))
    }

    @Test func 认不出的错误原样报出来() {
        #expect(OsascriptPrivilegedInstaller.error(stderr: "something odd") == .installerFailed("something odd"))
    }

    /// 去掉「管理员权限」后真的跑一遍 osascript：确认错误号能从 stderr 里读出来
    @Test func 真的跑osascript时能读出脚本的退出码() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let pkg = dir.url.appending(path: "S.pkg")
        try Data("not a pkg".utf8).write(to: pkg)
        let script = AuthorizationPromptInstaller.appleScript(for: pkg, sha256: Hashing.sha256(of: Data("not a pkg".utf8)))
            .replacingOccurrences(of: " with administrator privileges", with: "")
        let r = try Shell.run("/usr/bin/osascript", ["-e", script])
        #expect(r.status != 0)
        #expect(OsascriptPrivilegedInstaller.error(stderr: r.stderr)
                == PrivilegedInstallScript.error(status: PrivilegedInstallScript.signatureInvalid, message: ""))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter OsascriptInstallerTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'OsascriptPrivilegedInstaller'`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Install/PrivilegedInstaller.swift` 末尾加：

```swift
/// 应用里用：用 osascript 子进程弹系统授权框，执行和 AuthorizationPromptInstaller 一样的脚本。
/// 不在应用的主线程里跑 NSAppleScript，等用户输密码时界面不会卡住
public struct OsascriptPrivilegedInstaller: PrivilegedInstalling {
    public init() {}

    public func installPackage(_ pkg: URL, sha256: String?) async throws {
        let script = AuthorizationPromptInstaller.appleScript(for: pkg, sha256: sha256)
        let r = try Shell.run("/usr/bin/osascript", ["-e", script])
        guard r.status == 0 else { throw Self.error(stderr: r.stderr) }
    }

    /// osascript 失败时 stderr 末尾是「(错误号)」：-128 是用户点了取消，其余是提权脚本的退出码
    static func error(stderr: String) -> InstallError {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.hasSuffix(")"), let open = message.lastIndex(of: "("),
              let code = Int32(message[message.index(after: open)..<message.index(before: message.endIndex)]) else {
            return .installerFailed(message)
        }
        if code == -128 { return .cancelled }
        return PrivilegedInstallScript.error(status: code, message: message)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter OsascriptInstallerTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 4 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Install/PrivilegedInstaller.swift Tests/RimeKitTests/OsascriptInstallerTests.swift
git commit -m "feat: 用 osascript 子进程弹授权框（应用里用，不卡界面）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 应用的依赖集合、输入法服务、接管摘要

**Files:**
- Delete: `Sources/AppCore/AppCore.swift`
- Create: `Sources/AppCore/AppEnvironment.swift`、`Sources/AppCore/AppInputSource.swift`、`Sources/AppCore/TakeoverSummary.swift`
- Create: `Tests/RimeKitTests/Support/AppFakes.swift`
- Test: `Tests/RimeKitTests/TakeoverSummaryTests.swift`

**Interfaces:**
- Consumes: RimeKit 的 `Deployer`、`DeployWatcher`、`PackageStore`、`SquirrelInstaller`、`OsascriptPrivilegedInstaller`（任务 2）、`TISInputSourceService`、`RimeDictManager`、`TextReplacementReader`、`TakeoverProposal`、`TakeoverPreview`
- Produces:
  - `public struct AppEnvironment: Sendable`：`paths`、`locations`、`catalog`、`compiler`、`squirrel`、`inputSource`、`userDBTool`、`textReplacements`、`fetchPackage`、`installSquirrel`、`deployTimeout`、`activationTimeout`、`sleep`；`func deployer() -> Deployer`；`static func live() throws -> AppEnvironment`
  - `public struct AppInputSource: InputSourceControlling`
  - `public struct TakeoverSummary: Sendable, Equatable`（`schemas`、`options`、`appearance`、`preservedPatches`、`personalDicts`、`manualPhrases`、`textReplacementMatches`、`notes`、`replaced`、`unchanged`、`added`、`kept`、`blockedReason: String?`、`canConfirm: Bool`）；`static func make(_ proposal: TakeoverProposal, preview: TakeoverPreview, catalog: Catalog, blockedReason: String?) -> TakeoverSummary`
  - 测试辅助 `TransferFixtures.Machine.environment(…)`

- [ ] **Step 1: 写测试辅助和失败的测试**

`Tests/RimeKitTests/Support/AppFakes.swift`：

```swift
import Foundation
@testable import AppCore
@testable import RimeKit

extension TransferFixtures.Machine {
    /// 这台假 Mac 的应用依赖：包从自造的缓存里取，不联网
    func environment(
        input: FakeInputSource = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true)),
        compiler: FakeCompiler = FakeCompiler(),
        textReplacements: @escaping @Sendable () throws -> TextReplacementSnapshot = {
            TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0)
        },
        install: @escaping @Sendable () async throws -> InstallOutcome = { .alreadyInstalled("1.1.2") }
    ) -> AppEnvironment {
        let packages = self.packages
        return AppEnvironment(
            paths: paths, locations: locations, catalog: catalog, compiler: compiler, squirrel: squirrel,
            inputSource: input, userDBTool: tool, textReplacements: textReplacements,
            fetchPackage: { spec in
                guard let package = packages[spec.id] else { throw TakeoverError.missingPackage(spec.id) }
                return package
            },
            installSquirrel: install, deployTimeout: .milliseconds(20), activationTimeout: 5, sleep: { _ in })
    }
}
```

`Tests/RimeKitTests/TakeoverSummaryTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@Suite struct TakeoverSummaryTests {
    typealias F = TakeoverFixtures

    @Test func 摘要里只有名字和条数() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e)
        let preview = try TakeoverPreview.make(p, rime: e.rime, catalog: e.catalog, packages: e.packages,
                                               textReplacement: [F.fromTR], staging: e.dir.url.appending(path: "staging"))
        let s = TakeoverSummary.make(p, preview: preview, catalog: e.catalog, blockedReason: nil)
        #expect(s.schemas == ["五笔拼音（wb_py）", "五笔（wb）"])
        #expect(s.options == ["测试五笔 · 拼音词库：大词库"])
        #expect(s.appearance == ["候选字字号 24", "序号字号 20"])
        #expect(s.preservedPatches == ["default.custom.yaml：key_binder/bindings"])
        #expect(s.personalDicts == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(s.manualPhrases == 1)
        #expect(s.textReplacementMatches == 1)
        #expect(s.kept == ["notes.txt", "weasel.custom.yaml"])
        #expect(s.canConfirm)
        let text = "\(s)"
        for secret in ["私人短语", "替换短语", "私人词条", "私人五笔词"] {
            #expect(!text.contains(secret))
        }
    }

    @Test func 有阻止的原因时不能接管() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e)
        let preview = try TakeoverPreview.make(p, rime: e.rime, catalog: e.catalog, packages: e.packages,
                                               textReplacement: [], staging: e.dir.url.appending(path: "staging"))
        let s = TakeoverSummary.make(p, preview: preview, catalog: e.catalog, blockedReason: "读不了文本替换")
        #expect(!s.canConfirm)
        #expect(s.blockedReason == "读不了文本替换")
    }
}
```

（GenFixtures 里 wubi 包的名字是「测试五笔」，选项名「拼音词库」，选择 `ext` 的名字是「大词库」。）

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TakeoverSummaryTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'AppEnvironment'` / `'TakeoverSummary'`

- [ ] **Step 3: 实现**

删掉 `Sources/AppCore/AppCore.swift`。

`Sources/AppCore/AppEnvironment.swift`：

```swift
import Foundation
import RimeKit

/// 应用用到的所有外部依赖。正式运行用 live()；测试换成假的
public struct AppEnvironment: Sendable {
    public var paths: AppPaths
    public var locations: RimeLocations
    public var catalog: Catalog
    public var compiler: any RimeCompiler
    public var squirrel: any SquirrelControlling
    public var inputSource: any InputSourceControlling
    public var userDBTool: any UserDBTool
    /// 读 macOS 文本替换
    public var textReplacements: @Sendable () throws -> TextReplacementSnapshot
    /// 取一个上游包（下载或用缓存）
    public var fetchPackage: @Sendable (PackageSpec) async throws -> CachedPackage
    /// 下载、检查、安装鼠须管（会弹系统授权框）
    public var installSquirrel: @Sendable () async throws -> InstallOutcome
    public var deployTimeout: Duration
    /// 等用户在系统设置里添加输入法，最多等多少秒
    public var activationTimeout: Double
    public var sleep: @Sendable (Duration) async -> Void

    public func deployer() -> Deployer {
        Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                 watcher: DeployWatcher(locations: locations, timeout: deployTimeout, sleep: sleep))
    }

    public static func live() throws -> AppEnvironment {
        let paths = AppPaths.default
        let locations = RimeLocations.default
        let http = URLSessionHTTPClient()
        let store = PackageStore(paths: paths, http: http, retry: .standard)
        return AppEnvironment(
            paths: paths, locations: locations, catalog: try Catalog.builtIn(),
            compiler: DeployerCompiler(locations: locations),
            squirrel: SquirrelControl(locations: locations),
            inputSource: AppInputSource(),
            userDBTool: RimeDictManager(locations: locations),
            textReplacements: { try TextReplacementReader().snapshot() },
            fetchPackage: { spec in
                do {
                    return try await store.fetch(spec)
                } catch where PackageStore.isDownloadFailure(error) {
                    // 下载不了时先用本地缓存的旧版本（设计第 7 节）
                    if let old = store.latestCached(for: spec) { return old }
                    throw error
                }
            },
            installSquirrel: {
                try await SquirrelInstaller(paths: paths, locations: locations, http: http,
                                            privileged: OsascriptPrivilegedInstaller()).install()
            },
            deployTimeout: .seconds(120), activationTimeout: 600,
            sleep: { try? await Task.sleep(for: $0) })
    }
}
```

`Sources/AppCore/AppInputSource.swift`：

```swift
import Foundation
import RimeKit

/// 应用里用的输入法服务：TIS 的调用照旧（在主线程上做），等待时只 sleep，不再嵌套转 run loop。
/// 应用的主 run loop 本来就在转，系统的「输入源变了」通知会自己进来（阶段 4 的待改进项）
public struct AppInputSource: InputSourceControlling {
    let base = TISInputSourceService()

    public init() {}

    public func state() -> InputSourceState { base.state() }
    public func selectSquirrel() throws { try base.selectSquirrel() }
    public func openKeyboardSettings() throws { try base.openKeyboardSettings() }
    public func pump(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
}
```

`Sources/AppCore/TakeoverSummary.swift`：

```swift
import Foundation
import RimeKit

/// 接管预览给界面看的摘要：只有名字、文件名和条数，没有个人内容
public struct TakeoverSummary: Sendable, Equatable {
    public var schemas: [String]
    public var options: [String]
    public var appearance: [String]
    /// 「文件：键」
    public var preservedPatches: [String]
    public var personalDicts: [String]
    public var manualPhrases: Int
    public var textReplacementMatches: Int
    public var notes: [String]
    public var replaced: [String]
    public var unchanged: Int
    public var added: [String]
    public var kept: [String]
    /// 不能接管的原因（例如读不了文本替换）
    public var blockedReason: String?

    public var canConfirm: Bool { blockedReason == nil }

    public static func make(_ proposal: TakeoverProposal, preview: TakeoverPreview, catalog: Catalog,
                            blockedReason: String?) -> TakeoverSummary {
        let s = proposal.settings
        func schemaName(_ id: String) -> String {
            let name = catalog.packageOwning(schema: id)?.schemas.first { $0.id == id }?.name ?? id
            return "\(name)（\(id)）"
        }
        var options: [String] = []
        for packageID in s.options.keys.sorted() {
            guard let spec = catalog.package(packageID) else { continue }
            for option in spec.options {
                options.append("\(spec.name) · \(option.name)：\(s.choice(option, of: spec).name)")
            }
        }
        let a = s.appearance
        var look: [String] = []
        if let v = a.fontPoint { look.append("候选字字号 \(v)") }
        if let v = a.labelFontPoint { look.append("序号字号 \(v)") }
        if let v = a.commentFontPoint { look.append("注释字号 \(v)") }
        if let v = a.colorScheme { look.append("浅色配色 \(v)") }
        if let v = a.colorSchemeDark { look.append("深色配色 \(v)") }
        if let v = a.candidateListLayout { look.append(v == .linear ? "候选横排" : "候选竖排") }
        if let v = a.textOrientation { look.append(v == .horizontal ? "文字横排" : "文字竖排") }
        if let v = a.pageSize { look.append("每页 \(v) 个候选") }
        let preserved = s.preservedPatches.sorted { $0.key < $1.key }.flatMap { name, items in
            items.map { "\(name).custom.yaml：\($0.key)" }
        }
        return TakeoverSummary(
            schemas: s.schemas.map(schemaName), options: options, appearance: look, preservedPatches: preserved,
            personalDicts: proposal.personalDicts.map(\.lastPathComponent), manualPhrases: proposal.manualPhrases.count,
            textReplacementMatches: proposal.textReplacementMatches, notes: proposal.notes + preview.warnings,
            replaced: preview.replaced, unchanged: preview.unchanged.count, added: preview.added, kept: preview.kept,
            blockedReason: blockedReason)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TakeoverSummaryTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 2 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -3
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore Tests/RimeKitTests
git commit -m "feat: 应用的依赖集合、等待时不嵌套 run loop 的输入法服务、接管摘要

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 引导状态机 `SetupFlow`

**Files:**
- Create: `Sources/AppCore/SetupFlow.swift`
- Test: `Tests/RimeKitTests/SetupFlowTests.swift`

**Interfaces:**
- Consumes: `AppEnvironment`、`TakeoverSummary`（任务 3）；RimeKit 的 `SquirrelActivator`、`TakeoverSurvey`、`TakeoverAnalyzer`、`TakeoverPreview`、`TakeoverApplier`、`ImportArchive`、`Importer`、`UserDBTransfer`、`AppDataWriter`、`Deployer`
- Produces: `@MainActor @Observable public final class SetupFlow`
  - `public enum Step: Equatable { case checking, needInstall, needInputMethod(String?), waitingForInputMethod, needRestart, chooseStart(StartChoice), working(String), done([String]), failed(String) }`
  - `public enum StartChoice: Sendable, Equatable { case empty, existing(TakeoverSummary), unrecognized }`
  - `init(env: AppEnvironment)`；`step`；方法 `start()`、`install()`、`addInputMethod()`、`useSettings(_ settings: Settings)`、`confirmTakeover()`、`importFile(_ file: URL)`（都是 `async`）
  - 流程：
    - `start`：已经由应用管理 → `.done`；没装 → `.needInstall`；没注册或没添加 → `.needInputMethod(nil)`；否则看 Rime 目录。
    - 看 Rime 目录：空的 → `.chooseStart(.empty)`；认不出方案 → `.chooseStart(.unrecognized)`；有配置 → 下载对照用的包、识别、预览 → `.chooseStart(.existing(摘要))`。
    - 出错 → `.failed(说明)`；界面上「重试」就是再调一次 `start()`。

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/SetupFlowTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct SetupFlowTests {
    typealias T = TransferFixtures
    typealias F = TakeoverFixtures

    static let ready = InputSourceState(registered: true, enabled: true, selected: true)

    func phrases(_ list: [Phrase]) -> @Sendable () throws -> TextReplacementSnapshot {
        { TextReplacementSnapshot(usable: list, badShortcut: 0, badPhrase: 0) }
    }

    @Test func 已经设置好的不再引导() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(m.paths)
        let flow = SetupFlow(env: m.environment())
        await flow.start()
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
    }

    @Test func 没装鼠须管时先装() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try FileManager.default.removeItem(at: m.locations.squirrelApp)
        let app = m.locations.squirrelApp
        let flow = SetupFlow(env: m.environment(input: FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false)),
                                                install: {
            // 模拟装好：放一个可执行的 rime_deployer
            let deployer = app.appending(path: "Contents/MacOS/rime_deployer")
            try FileManager.default.createDirectory(at: deployer.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: deployer)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deployer.path)
            return .installed("1.1.2", previous: nil)
        }))
        await flow.start()
        #expect(flow.step == .needInstall)
        await flow.install()
        #expect(flow.step == .needInputMethod(nil))
    }

    @Test func 取消授权时说清楚() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try FileManager.default.removeItem(at: m.locations.squirrelApp)
        let flow = SetupFlow(env: m.environment(install: { throw InstallError.cancelled }))
        await flow.start()
        await flow.install()
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("取消"))
    }

    @Test func 添加输入法后看Rime目录_空的就选起步方案() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        input.enableAfterPumps = 2
        let flow = SetupFlow(env: m.environment(input: input))
        await flow.start()
        #expect(flow.step == .needInputMethod(nil))
        await flow.addInputMethod()
        #expect(flow.step == .chooseStart(.empty))
        #expect(input.calls.contains("open"))
    }

    @Test func 等添加输入法超时() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let flow = SetupFlow(env: m.environment(input: FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))))
        await flow.addInputMethod()
        guard case .needInputMethod(let note) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(note?.contains("还没看到") == true)
    }

    @Test func 选起步方案后写好配置() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let flow = SetupFlow(env: m.environment())
        await flow.start()
        #expect(flow.step == .chooseStart(.empty))
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(try SettingsStore(paths: m.paths).load()?.schemas == ["py"])
        #expect(!(try Ledger.load(m.paths).entries.isEmpty))
        #expect(FileManager.default.fileExists(atPath: m.locations.rimeDirectory.appending(path: "py.schema.yaml").path))
    }

    @Test func 编译失败时说清楚_什么都不保存() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        let flow = SetupFlow(env: m.environment(compiler: failing))
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("编译不过"))
        #expect(!FileManager.default.fileExists(atPath: m.paths.settingsFile.path))
    }

    @Test func 有已有配置时先预览_点了才接管() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.wubiSample(m.packages, into: m.locations.rimeDirectory)
        let flow = SetupFlow(env: m.environment(textReplacements: phrases([F.fromTR])))
        await flow.start()
        guard case .chooseStart(.existing(let summary)) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(summary.schemas == ["五笔拼音（wb_py）", "五笔（wb）"])
        #expect(summary.canConfirm)
        #expect(!FileManager.default.fileExists(atPath: m.paths.settingsFile.path))   // 预览不写任何东西
        await flow.confirmTakeover()
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(try SettingsStore(paths: m.paths).load()?.schemas == ["wb_py", "wb"])
    }

    @Test func 读不了文本替换时不能接管() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.wubiSample(m.packages, into: m.locations.rimeDirectory)
        struct Unreadable: Error, CustomStringConvertible { var description: String { "数据库打不开" } }
        let flow = SetupFlow(env: m.environment(textReplacements: { throw Unreadable() }))
        await flow.start()
        guard case .chooseStart(.existing(let summary)) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(!summary.canConfirm)
        #expect(summary.blockedReason?.contains("数据库打不开") == true)
        await flow.confirmTakeover()
        #expect(!FileManager.default.fileExists(atPath: m.paths.settingsFile.path))
    }

    @Test func 认不出方案时让用户选起步方案() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.put("随手记\n", "notes.txt", in: m.locations.rimeDirectory)
        let flow = SetupFlow(env: m.environment())
        await flow.start()
        #expect(flow.step == .chooseStart(.unrecognized))
    }

    @Test func 从导出文件导入() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let flow = SetupFlow(env: b.environment())
        await flow.start()
        await flow.importFile(file)
        guard case .done = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        #expect(b.tool.dbs["wb_py"] == T.snapshot)
    }

    @Test func 不是导出文件时说清楚() async throws {
        let b = try T.machine(withSettings: false); defer { b.dir.remove() }
        let file = b.dir.url.appending(path: "x.zip")
        try Data("不是".utf8).write(to: file)
        let flow = SetupFlow(env: b.environment())
        await flow.importFile(file)
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("不是 squirrel-macos 的导出文件"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SetupFlowTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'SetupFlow'`

- [ ] **Step 3: 实现**

`Sources/AppCore/SetupFlow.swift`：

```swift
import Foundation
import Observation
import RimeKit

public enum StartChoice: Sendable, Equatable {
    /// Rime 目录里没有配置：选起步方案，或者从导出文件导入
    case empty
    /// 有能认出来的配置：先看预览，用户确认后接管
    case existing(TakeoverSummary)
    /// 有配置但认不出方案：选起步方案（原来的文件先完整备份），或者导入
    case unrecognized
}

/// 第一次打开时的引导（设计 6.2）：装鼠须管 → 添加输入法 → 起步方案 / 接管 / 导入。
/// 只调用 RimeKit；界面按 step 显示，按钮调用对应的方法
@MainActor @Observable
public final class SetupFlow {
    public enum Step: Equatable {
        case checking
        case needInstall
        /// 附带说明（例如等超时了）
        case needInputMethod(String?)
        case waitingForInputMethod
        /// 重新注册了输入源：要退出应用再打开（同一个进程里 TIS 的状态不会更新）
        case needRestart
        case chooseStart(StartChoice)
        /// 正在做的事（下载、写入、部署……）
        case working(String)
        /// 完成，附带说明和提醒
        case done([String])
        case failed(String)
    }

    public private(set) var step: Step = .checking
    let env: AppEnvironment
    /// 预览过、可以接管的结果
    private var pendingTakeover: (proposal: TakeoverProposal, packages: [String: CachedPackage], textReplacement: [Phrase])?

    public init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: 开始

    public func start() async {
        step = .checking
        let managed = (try? Ledger.load(env.paths))?.entries.isEmpty == false
        if managed, (try? SettingsStore(paths: env.paths).load()) != nil {
            step = .done(["鼠须管已经由这个应用管理了"])
            return
        }
        guard env.locations.squirrelInstalled else {
            step = .needInstall
            return
        }
        let state = env.inputSource.state()
        guard state.registered, state.enabled else {
            step = .needInputMethod(nil)
            return
        }
        await prepareStart()
    }

    // MARK: 第一步：安装鼠须管

    public func install() async {
        step = .working("正在下载、检查鼠须管的安装包。之后会弹出系统授权框，请输入这台 Mac 的登录密码……")
        do {
            let install = env.installSquirrel
            _ = try await offMain { try await install() }
            step = .needInputMethod(nil)
        } catch InstallError.cancelled {
            step = .failed("你取消了授权，鼠须管没有安装。准备好了再点「重试」")
        } catch {
            step = .failed("安装鼠须管失败：\(error)")
        }
    }

    // MARK: 第二步：添加输入法

    public func addInputMethod() async {
        step = .waitingForInputMethod
        let activator = SquirrelActivator(
            locations: env.locations, inputSource: env.inputSource, squirrel: env.squirrel,
            watcher: DeployWatcher(locations: env.locations, timeout: env.deployTimeout, sleep: env.sleep),
            timeout: env.activationTimeout)
        do {
            switch try await offMain({ try await activator.activate() }) {
            case .ready:
                await prepareStart()
            case .timedOut:
                step = .needInputMethod("等了很久还没看到鼠须管被添加。添加好后再点一次「打开系统设置」")
            case .reregistered:
                step = .needRestart
            case .notRegistered:
                step = .failed("系统里没有鼠须管的输入源，重新注册也没用。请重新安装鼠须管")
            }
        } catch {
            step = .failed("\(error)")
        }
    }

    // MARK: 第三步：看 Rime 目录

    func prepareStart() async {
        step = .working("正在看 Rime 目录里有没有已有的配置……")
        do {
            let rime = env.locations.rimeDirectory
            let catalog = env.catalog
            let survey = try await offMain { try TakeoverSurvey.scan(rime, catalog: catalog) }
            if survey.isEmpty {
                step = .chooseStart(.empty)
                return
            }
            guard !survey.schemas.isEmpty else {
                step = .chooseStart(.unrecognized)
                return
            }
            var packages = try await fetch(try env.catalog.installOrder(for: survey.packages))
            var textReplacement: [Phrase] = []
            var blocked: String?
            do {
                textReplacement = try env.textReplacements().usable
            } catch {
                // 读不到就分不出哪些短语来自文本替换：不能接管（和 rimectl takeover 一样）
                blocked = "读不了 macOS 文本替换（\(error)），分不出哪些短语来自文本替换，暂时不能接管"
            }
            step = .working("正在识别已有的配置……")
            let found = packages
            let replacements = textReplacement
            let proposal = try await offMain {
                try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: found, textReplacement: replacements)
            }
            let missing = try proposal.settings.requiredPackages(env.catalog).filter { packages[$0.id] == nil }
            packages.merge(try await fetch(missing)) { old, _ in old }
            step = .working("正在比对接管后会变的文件……")
            let all = packages
            let staging = env.paths.staging
            let preview = try await offMain {
                try TakeoverPreview.make(proposal, rime: rime, catalog: catalog, packages: all,
                                         textReplacement: replacements, staging: staging)
            }
            pendingTakeover = blocked == nil ? (proposal, packages, textReplacement) : nil
            step = .chooseStart(.existing(TakeoverSummary.make(proposal, preview: preview, catalog: env.catalog,
                                                               blockedReason: blocked)))
        } catch {
            step = .failed("\(error)")
        }
    }

    /// 取这些包，界面上显示进度
    func fetch(_ specs: [PackageSpec]) async throws -> [String: CachedPackage] {
        var result: [String: CachedPackage] = [:]
        for (index, spec) in specs.enumerated() {
            step = .working("正在下载方案：\(spec.name)（\(index + 1)/\(specs.count)）……")
            result[spec.id] = try await env.fetchPackage(spec)
        }
        return result
    }

    // MARK: 起步方案

    public func useSettings(_ settings: Settings) async {
        do {
            let packages = try await fetch(try settings.requiredPackages(env.catalog))
            step = .working("正在生成配置、写入、部署……")
            let input = GenerationInput(settings: settings, catalog: env.catalog, packages: packages,
                                        personal: .empty, textReplacementPhrases: [])
            let paths = env.paths
            // Rime 目录里认不出的同名文件也覆盖：先完整备份，第一次的这份永久保留
            let deployer = env.deployer()
            let outcome = try await offMain {
                try await deployer.apply(input, options: ApplyOptions(overwriteExternalChanges: true),
                                         afterWrite: { try AppDataWriter.replace(settings: settings, dicts: [], phrases: [], paths: paths) })
            }
            finish(outcome, notes: [])
        } catch {
            step = .failed("\(error)")
        }
    }

    // MARK: 接管

    public func confirmTakeover() async {
        guard let pending = pendingTakeover else {
            await prepareStart()
            return
        }
        step = .working("正在接管：完整备份、写入、部署……")
        do {
            let applier = TakeoverApplier(deployer: env.deployer())
            let catalog = env.catalog
            let outcome = try await offMain {
                try await applier.confirm(pending.proposal, catalog: catalog, packages: pending.packages,
                                          textReplacement: pending.textReplacement, force: true)
            }
            pendingTakeover = nil
            finish(outcome, notes: [])
        } catch {
            step = .failed("\(error)")
        }
    }

    // MARK: 从导出文件导入

    public func importFile(_ file: URL) async {
        step = .working("正在读取导出文件……")
        let work = env.paths.staging.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let accessing = file.startAccessingSecurityScopedResource()
        defer { if accessing { file.stopAccessingSecurityScopedResource() } }
        do {
            let catalog = env.catalog
            let archive = try await offMain { try ImportArchive.open(file, catalog: catalog, into: work) }
            let settings = archive.manifest.settings
            let packages = try await fetch(try settings.requiredPackages(env.catalog))
            var notes = archive.warnings
            var textReplacement: [Phrase] = []
            if settings.textReplacement.sync {
                do {
                    textReplacement = try env.textReplacements().usable
                } catch {
                    notes.append("读不了 macOS 文本替换（\(error)），这次先不带文本替换的短语")
                }
            }
            step = .working(archive.userDB.isEmpty
                ? "正在写入、部署……"
                : "正在写入、部署，然后合并输入习惯（输入法会暂停几秒）……")
            let importer = Importer(deployer: env.deployer(),
                                    userDB: UserDBTransfer(tool: env.userDBTool, squirrel: env.squirrel, sleep: env.sleep))
            let replacements = textReplacement
            let report = try await offMain {
                try await importer.run(archive, catalog: catalog, packages: packages, textReplacement: replacements)
            }
            if let previous = report.previous { notes.append("应用里原来的设置和个人内容另存在：\(previous.path)") }
            if let error = report.userDBError { notes.append("输入习惯没有合并上：\(error)。配置已经导入好了，可以再导入一次") }
            finish(report.outcome, notes: notes)
        } catch {
            step = .failed("\(error)")
        }
    }

    /// 重活（读写文件、复制方案包、等部署）放到后台做，界面不卡
    func offMain<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Task.detached(operation: body).value
    }

    // MARK: 结果

    func finish(_ outcome: ApplyOutcome, notes: [String]) {
        switch outcome {
        case .applied(let report):
            var lines = ["鼠须管已经设置好了，可以打字了"]
            if !report.deploy.finished { lines.append("等了很久还没看到部署完成，可能还在部署；过一会儿再试试打字") }
            lines += report.deploy.errors.map { "部署时有错误：\($0)" }
            lines += report.warnings + notes
            step = .done(lines)
        case .compileFailed(let errors):
            step = .failed((["新配置编译不过，没有写入："] + errors).joined(separator: "\n"))
        case .externalChanges(let changes):
            step = .failed((["这些文件不能写，没有写入："] + changes.map(\.description)).joined(separator: "\n"))
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter SetupFlowTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -5`
Expected: 12 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -3
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore/SetupFlow.swift Tests/RimeKitTests/SetupFlowTests.swift
git commit -m "feat: 第一次打开的引导：装鼠须管、添加输入法、起步方案 / 接管 / 导入

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 引导的界面

**Files:**
- Modify: `Sources/AppUI/RootView.swift`
- Create: `Sources/AppUI/TakeoverPreviewView.swift`
- Modify: `Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`

**Interfaces:**
- Consumes: `SetupFlow`、`StartChoice`、`TakeoverSummary`、`AppEnvironment.live()`（任务 3、4）
- Produces: `public struct RootView: View { init(flow: SetupFlow?) }`；`TakeoverPreviewView`

视图里不写逻辑，只按 `flow.step` 显示，按钮调用 `flow` 的方法。窗口固定宽 560，内容放在 `ScrollView` 里。

- [ ] **Step 1: 写视图**

`Sources/AppUI/RootView.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI
import UniformTypeIdentifiers

/// 应用的根视图：现在只有第一次打开的引导（主窗口在阶段 8b）
public struct RootView: View {
    let flow: SetupFlow?

    public init(flow: SetupFlow?) {
        self.flow = flow
    }

    public var body: some View {
        Group {
            if let flow {
                SetupView(flow: flow)
                    .task { await flow.start() }
            } else {
                Message(symbol: "exclamationmark.triangle", title: "应用里找不到方案清单",
                        lines: ["应用好像坏了，请重新下载"])
            }
        }
        .frame(width: 560)
        .frame(minHeight: 360)
    }
}

struct SetupView: View {
    let flow: SetupFlow
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                Task { await flow.importFile(url) }
            }
        }
    }

    @ViewBuilder var content: some View {
        switch flow.step {
        case .checking:
            Working(text: "正在检查……")
        case .working(let text):
            Working(text: text)
        case .needInstall:
            Message(symbol: "arrow.down.circle", title: "第一步：安装鼠须管",
                    lines: ["鼠须管是 Rime 输入法在 Mac 上的版本。应用会从官方 GitHub 下载最新的安装包，检查签名和公证，然后安装。",
                            "安装时会弹出系统授权框，需要输入这台 Mac 的登录密码。"])
            Button("安装鼠须管") { Task { await flow.install() } }
                .buttonStyle(.borderedProminent)
        case .needInputMethod(let note):
            Message(symbol: "keyboard", title: "第二步：添加输入法",
                    lines: ["macOS 不允许应用自己添加输入法，要你在系统设置里加一次：",
                            "「键盘 → 文字输入 → 输入法 → 编辑… → + → 简体中文 → 鼠须管」",
                            "点下面的按钮会打开系统设置；加好后应用会自动继续。"])
            if let note { Note(text: note) }
            Button("打开系统设置") { Task { await flow.addInputMethod() } }
                .buttonStyle(.borderedProminent)
        case .waitingForInputMethod:
            Working(text: "请在系统设置里添加「鼠须管」（简体中文下面）。加好后这里会自动继续……")
        case .needRestart:
            Message(symbol: "arrow.clockwise", title: "请退出应用再打开",
                    lines: ["系统里鼠须管的输入源丢了，已经重新注册。要退出这个应用再重新打开，才能看到最新的状态。"])
            Button("退出应用") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderedProminent)
        case .chooseStart(let choice):
            chooseStart(choice)
        case .done(let lines):
            Message(symbol: "checkmark.circle", title: "设置好了", lines: lines)
            Button("重新检查") { Task { await flow.start() } }
        case .failed(let message):
            Message(symbol: "exclamationmark.triangle", title: "出了点问题", lines: [message])
            Button("重试") { Task { await flow.start() } }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder func chooseStart(_ choice: StartChoice) -> some View {
        switch choice {
        case .empty:
            Message(symbol: "sparkles", title: "第三步：选一个起步方案",
                    lines: ["以后可以随时在应用里改方案、调外观。用过这个应用、手里有导出文件的话，也可以直接导入。"])
            starterButtons
        case .unrecognized:
            Message(symbol: "questionmark.folder", title: "第三步：选一个起步方案",
                    lines: ["Rime 目录里已经有配置，但里面的方案这个应用还不认识。",
                            "选一个起步方案后，原来的文件会先完整备份（这份备份永久保留），认不出的文件原样留着。"])
            starterButtons
        case .existing(let summary):
            Message(symbol: "doc.text.magnifyingglass", title: "第三步：接管已有的配置",
                    lines: ["Rime 目录里已经有配置。下面是应用认出来的内容，和接管后会变的文件。确认后才会改：会先完整备份（这份备份永久保留）。"])
            TakeoverPreviewView(summary: summary)
            HStack {
                Button("接管") { Task { await flow.confirmTakeover() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!summary.canConfirm)
                Menu("改用起步方案") {
                    ForEach(Starter.allCases, id: \.self) { starter in
                        Button(starter.displayName) { Task { await flow.useSettings(.starter(starter)) } }
                    }
                }
                .fixedSize()
                Button("从导出文件导入…") { importing = true }
            }
        }
    }

    var starterButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Starter.allCases, id: \.self) { starter in
                Button(starter.displayName) { Task { await flow.useSettings(.starter(starter)) } }
            }
            Divider()
            Button("从导出文件导入…") { importing = true }
        }
    }
}

struct Message: View {
    let symbol: String
    let title: String
    let lines: [String]

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title2.bold())
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Working: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Note: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

`Sources/AppUI/TakeoverPreviewView.swift`：

```swift
import AppCore
import SwiftUI

/// 接管预览：认出来的设置、个人内容的条数、接管后会变的文件（只有名字和条数）
struct TakeoverPreviewView: View {
    let summary: TakeoverSummary

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Row(title: "方案（第一个是默认）", items: summary.schemas)
                if !summary.options.isEmpty { Row(title: "选项", items: summary.options) }
                Row(title: "外观", items: summary.appearance.isEmpty ? ["都是方案默认的"] : summary.appearance)
                if !summary.preservedPatches.isEmpty { Row(title: "保留你改过的", items: summary.preservedPatches) }
                Row(title: "个人内容", items: [
                    "个人词库 \(summary.personalDicts.count) 个" + (summary.personalDicts.isEmpty ? "" : "（\(summary.personalDicts.joined(separator: "、"))）"),
                    "手动短语 \(summary.manualPhrases) 条",
                ] + (summary.textReplacementMatches > 0
                    ? ["和 macOS 文本替换一样的短语 \(summary.textReplacementMatches) 条（接管后打开文本替换同步）"] : []))
                ForEach(Array((summary.notes + (summary.blockedReason.map { [$0] } ?? [])).enumerated()), id: \.offset) { _, note in
                    Note(text: note)
                }
                Divider()
                Text("接管后：换掉 \(summary.replaced.count) 个文件，内容不变 \(summary.unchanged) 个，新加 \(summary.added.count) 个，原样保留 \(summary.kept.count) 个")
                    .font(.callout)
                Files(title: "换掉", files: summary.replaced)
                Files(title: "新加", files: summary.added)
                Files(title: "原样保留", files: summary.kept)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct Row: View {
        let title: String
        let items: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    struct Files: View {
        let title: String
        let files: [String]

        var body: some View {
            if !files.isEmpty {
                DisclosureGroup("\(title)（\(files.count) 个）") {
                    Text(files.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
```

`Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`：

```swift
import AppCore
import AppUI
import SwiftUI

@main
struct SquirrelMacOSApp: App {
    @State private var flow: SetupFlow? = try? SetupFlow(env: AppEnvironment.live())

    var body: some Scene {
        WindowGroup("squirrel-macos") {
            RootView(flow: flow)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 2: 编译，打包**

Run:
```bash
swift build 2>&1 | grep -E "error:|warning:" | head -5
./tools/app/build-app.sh
swift test 2>&1 | grep -E "error:|Test run" | tail -2
```
Expected：没有 error、warning；打包成功；测试全部通过。**不要在宿主机上打开应用。**

编译报 `@State` 初始值在主线程外初始化之类的并发错误时：改成在 `init()` 里用 `_flow = State(initialValue: …)` 初始化（`App` 的 `init` 在主线程上），记一条 Ruling。

- [ ] **Step 3: 提交**

```bash
git add Sources/AppUI Sources/SquirrelMacOSApp
git commit -m "feat: 第一次打开的引导界面

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 把应用放进测试机的脚本

**Files:**
- Create: `tools/vm/install-app.sh`

**Interfaces:**
- Consumes: `tools/app/build-app.sh`（任务 1）、`tools/vm/vm.sh`
- Produces: `./tools/vm/install-app.sh <测试机>`：打包，复制到测试机的 `~/Applications/squirrel-macos.app`（先删旧的），去掉隔离属性，在桌面会话里 `open` 它

- [ ] **Step 1: 写脚本**

`tools/vm/install-app.sh`（`chmod +x`）：

```bash
#!/bin/bash
# 打包应用，放进测试机的 ~/Applications 并打开。用法：./tools/vm/install-app.sh <测试机名字>
# 测试机的共享文件夹只读，而且宿主机原地重编后直接运行可能被杀，所以先复制到测试机本地。
set -euo pipefail
cd "$(dirname "$0")/../.."
vm="${1:?用法：$0 <测试机名字>}"
app="$(./tools/app/build-app.sh)"
./tools/vm/vm.sh ssh "$vm" "pkill -x SquirrelMacOSApp || true; mkdir -p ~/Applications && rm -rf ~/Applications/squirrel-macos.app && cp -R '/Volumes/My Shared Files/project/$app' ~/Applications/ && xattr -cr ~/Applications/squirrel-macos.app && sudo launchctl asuser \$(id -u) sudo -u tester open ~/Applications/squirrel-macos.app"
echo "已在 $vm 里打开 ~/Applications/squirrel-macos.app"
```

- [ ] **Step 2: 检查语法，提交**

Run: `bash -n tools/vm/install-app.sh && echo 语法正常`
Expected: 语法正常

```bash
git add tools/vm/install-app.sh
git commit -m "feat: 把应用放进测试机并打开的脚本

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 测试机里由用户走一遍引导

**Files:**
- Create: `docs/phase8a-vm-log.md`

**Interfaces:**
- Consumes: 任务 1–6
- Produces: 实测记录；发现的问题先写假依赖的失败测试再修（逻辑在 `SetupFlow`），界面问题直接改视图并记录

每一步都用 AskUserQuestion 问用户看到了什么（至少两个选项，带「有问题，写在备注里」）。

- [ ] **Step 1: 新电脑，从零开始（`squirrel-app`）**

```bash
./tools/vm/vm.sh new squirrel-app
```

请用户登录桌面，然后 `./tools/vm/install-app.sh squirrel-app`。请用户按界面操作，并告诉你每一步看到的：

1. 「第一步：安装鼠须管」→ 点「安装鼠须管」→ 授权框里**先点「取消」**：应该显示「你取消了授权…」和「重试」。
2. 点「重试」→「安装鼠须管」→ 这次输入密码：装好后到「第二步：添加输入法」。
3. 点「打开系统设置」→ 在系统设置里添加鼠须管：应用自动继续到「第三步：选一个起步方案」。
4. 选「雾凇拼音（全拼）」：显示「正在下载方案…」，再到「设置好了」。
5. 用户打字：`nihao` → 你好。

然后关掉应用再打开（`./tools/vm/vm.sh ssh squirrel-app 'sudo launchctl asuser $(id -u) sudo -u tester open ~/Applications/squirrel-macos.app'`）：应该直接显示「设置好了 / 鼠须管已经由这个应用管理了」。

- [ ] **Step 2: 已有配置的电脑（`squirrel-dev`，接管）**

`squirrel-dev` 的 Rime 目录由 `/tmp/rk` 管理；应用用的是默认的数据目录（`~/Library/Application Support/squirrel-macos`，还是空的），所以它会把这当成「已有配置」。

```bash
./tools/vm/vm.sh ssh squirrel-dev 'ls ~/Library/Application\ Support/squirrel-macos 2>/dev/null || echo 空的'
./tools/vm/install-app.sh squirrel-dev
```

请用户看「第三步：接管已有的配置」的预览：方案是雾凇拼音、外观「候选字字号 24，每页 7 个候选」、「换掉 0 个文件」。点「接管」→「设置好了」，打字正常。

然后还原：`./tools/vm/vm.sh ssh squirrel-dev 'rm -rf ~/Library/Application\ Support/squirrel-macos'`（Rime 目录的内容没变，`/tmp/rk` 仍然对得上：`rimectl status --data-dir /tmp/rk` 没有外部改动；在测试机里跑 rimectl 前先复制到本地，见 `CLAUDE.md`）。

- [ ] **Step 3: 从导出文件导入（`squirrel-app`）**

在 `squirrel-dev` 里用 rimectl 导出（先复制到本地再运行，导出到 `/tmp`，再拷到宿主机 `.build/phase8a-export.zip`，做法同阶段 6）。在 `squirrel-app` 里清掉应用数据（`rm -rf ~/Library/Application\ Support/squirrel-macos`），把导出文件放到测试机的 `~/Downloads`：

```bash
./tools/vm/vm.sh ssh squirrel-app "cp '/Volumes/My Shared Files/project/.build/phase8a-export.zip' ~/Downloads/"
```

打开应用：这时 Rime 目录里是步骤 1 生成的雾凇配置，会显示「接管」预览。请用户点「从导出文件导入…」选 `~/Downloads/phase8a-export.zip`：应该显示「正在写入、部署，然后合并输入习惯…」，再到「设置好了」（带「原来的设置另存在…」）。打字：外观和 `squirrel-dev` 一样（24 号、每页 7 个）。

- [ ] **Step 4: 收尾**

删掉 `squirrel-app`（`./tools/vm/vm.sh rm squirrel-app`）、`.build/phase8a-export.zip`、测试机里的临时文件。

`docs/phase8a-vm-log.md`：每一步用户看到的（界面截图不用存，用文字写）、发现的问题和怎么修的。

```bash
git add docs/phase8a-vm-log.md
git commit -m "docs: 阶段 8a 测试机实测记录（第一次打开的引导）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 更新文档

**Files:**
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`（阶段 8 拆成 8a、8b）
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（第 3 节「两个技术细节」里的管理员权限、8.3 界面）
- Modify: `CLAUDE.md`、`README.md`

- [ ] **Step 1: 路线图**

阶段 8 那一行换成两行：

```markdown
| 8a | 应用骨架 + 第一次打开的引导 | `squirrel-macos.app`（`tools/app/build-app.sh` 打包，临时签名）：装鼠须管、添加输入法、起步方案 / 接管 / 导入（已完成，2026-10-15） | 宿主机单元测试 + 测试机里由用户点一遍 |
| 8b | 主窗口 | 方案、外观、文本替换、导入导出、备份还原、诊断；改了点「应用改动」才生效；出错提示 | 宿主机单元测试 + 测试机里由用户检查 |
```

- [ ] **Step 2: 设计文档**

第 3 节「两个技术细节」的「管理员权限」那一条里，`应用用系统授权弹窗（NSAppleScript 执行 …）` 改成 `应用用系统授权弹窗（osascript 子进程执行 do shell script … with administrator privileges，不在主线程里跑，不卡界面；阶段 8a 定下）`。

8.3 末尾加：

```markdown
- 打包：不建 Xcode 工程。SwiftPM 的可执行目标 `SquirrelMacOSApp` + `tools/app/build-app.sh` 拼成 `.app`（RimeKit 的资源包放在 `Contents/Resources`），开发期间临时签名。逻辑在 `AppCore`（不含 SwiftUI，宿主机用假依赖测），视图在 `AppUI`。**不在宿主机上运行应用**（它会读写真实的 `~/Library/Rime`）；用 `tools/vm/install-app.sh <测试机>` 放进测试机打开。
```

- [ ] **Step 3: CLAUDE.md、README**

- `CLAUDE.md` 第一段阶段状态改成「阶段 0–7、8a 已完成（…；文本替换同步；应用骨架和第一次打开的引导），下一步写阶段 8b（主窗口）的计划」；「工作方式」里加一条：`- 应用（SquirrelMacOSApp）不在宿主机上运行，只编译和跑单元测试；用 ./tools/vm/install-app.sh <测试机> 放进测试机打开。`
- `README.md` 加一行：`- 应用：./tools/app/build-app.sh 打包成 .build/app/squirrel-macos.app；只在测试机里打开（./tools/vm/install-app.sh 测试机名字）`（命令用反引号）。

- [ ] **Step 4: 检查，提交**

```bash
grep -n "| 8a |" docs/superpowers/plans/2026-10-15-roadmap.md
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 8a 完成：路线图拆成 8a、8b，打包和授权框的做法写进设计

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
