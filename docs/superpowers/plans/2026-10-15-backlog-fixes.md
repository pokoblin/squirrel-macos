# 待改进项修复 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修掉 [待改进项清单](../../backlog.md) 里应用用户会碰到的 34 条，外加 6 条顺手的开发工具问题，一共 40 条。在干净测试机里走一遍改过的流程，然后出 0.1.1。

**Architecture:**
- 不加新功能，只在原来的位置修。
- 每条修复都要先有能复现问题的测试，看着它失败（RED），修好后通过（GREEN）。
- 视图层的改动（按钮、确认框）在测试机里由你检查。
- 清单里「以后」「不修」的条目不动。

**Tech Stack:** 现有 Swift 6.4 工程（RimeKit、AppCore、AppUI、rimectl）、Swift Testing、shell 脚本。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)。每条修复涉及的章节写在任务里：
- 6.2 引导；
- 6.4 导入（决定 2 改了一句）；
- 5.2 接管识别；
- 第 7 节 出错处理。

另见：清单 [docs/backlog.md](../../backlog.md)（每条的编号就是清单里的 `#`）；发布步骤 [docs/release.md](../../release.md)。

## 已经和你确认的

- 范围：修应用用户会碰到的；rimectl 专用的、要应用和 rimectl 同时运行才会出的竞争问题，先不修，留在清单里。

## 本计划要定的事（计划里的做法，请确认）

| # | 问题 | 计划里的做法 | 理由 |
|---|---|---|---|
| 1 | 取消授权后显示什么 | 回到「第一步：安装鼠须管」，上面加一句「你取消了授权，鼠须管没有安装…」，不再显示出错页 | 取消不是出错 |
| 2 | 每次导入都多一份永久备份（#27） | 应用还没管过 Rime 目录（账本是空的）时，「导入前」备份照旧永久保留；已经由应用管理时，改成普通备份，跟着最近 10 份轮换。另存的「导入前」zip 只留最近 10 个。设计 6.4 改一句 | 永久备份是为了保护原来不是应用写的配置；应用自己写的配置，普通备份就够了 |
| 3 | 解压大小上限（#44） | 解压前用系统的 `zipinfo -t` 看总大小，超过 2 GB 就不解压，提示「文件太大」。导入和下载方案包都用这个检查 | 雾凇解开后远小于 2 GB。注意：zip 里写的大小可能被恶意改小，这个检查挡得住损坏的、意外的大文件，挡不住精心构造的 |
| 4 | 「改用起步方案」（#2） | 点了先弹确认：「认出来的个人词库、短语不会带过去；原来的文件会先完整备份（永久保留）」 | 不能点一下就写 |
| 5 | 接管时的边角写法（#18、#39 以外） | #18、#39 改识别规则；#51、#57、#62、#65 只在预览的「提醒」里加一句，不新增功能 | 这些写法很少见，先让用户知道 |
| 6 | 鼠须管版本号不是纯数字（#47） | 认不出时按原文比较，相同就算已装；安装包文件名固定为 `Squirrel.pkg` | 上游发 rc、beta 时不反复重装 |
| 7 | 暂存区清理（#60） | 打开应用时，删掉暂存区里 1 小时以前的东西 | 暂存区只放临时文件；留 1 小时是为了不碰正在跑的操作 |
| 8 | 出 0.1.1 | 修完、测试机里走过后，按 `docs/release.md` 出 0.1.1（预发布）。打 tag、发 Release 前先问你 | 0.1.0 的用户能拿到修复 |

## Global Constraints

- 宿主机不运行应用，不碰 `~/Library/Rime`、`/Library/Input Methods`、输入法状态。
- 每条修复：先写测试看它失败，再修，再跑全部测试（`swift test`）。视图层和 shell 脚本没有单元测试的，用任务里写的命令检查。
- 界面和提示用简单直白的中文；不让用户去运行 rimectl。
- 隐私：文本替换只统计条数。
- 测试机：
  - 新克隆 `squirrel-fix`，测完删掉；
  - 同时最多两台；
  - 登录桌面、输密码、在系统设置里添加输入法、在界面上点按钮，由你来做；
  - 文件放 `/Users/Shared`；
  - 共享文件夹一时看不到新文件时，用 `vm.sh ssh … "cat > …" < 文件` 传。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。打 tag、发 Release 前先问。
- 改完一条，把 `docs/backlog.md` 里那条的「处理」改成「已修（0.1.1）」（在任务 10 统一改）。

## Review Focus

1. 引导里取消授权、输错密码、等部署时，界面上的说法和按钮（任务 1 有单元测试，任务 9 实测）。
2. 还原第 11 份最旧的备份后它还在；备份失败不留下 `.partial`（任务 3 有测试）。
3. 已由应用管理时导入不再加永久备份，第一次导入仍然加（任务 4 有测试）。
4. 接管识别的改动不影响阶段 5 的接管测试（`TakeoverAnalyzerTests` 全部通过）。
5. 发布脚本加了 git 检查后，干净的工作区仍能打包（任务 8、11 实际跑一次）。

---

## 文件结构

| 文件 | 做什么 |
|---|---|
| `Sources/AppCore/SetupFlow.swift`、`Sources/AppUI/RootView.swift`、`Sources/AppCore/AppState.swift`、`Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`、`Sources/RimeKit/Install/SquirrelActivator.swift`、`Sources/RimeKit/Install/PrivilegedInstaller.swift` | 任务 1 |
| `Sources/RimeKit/TextReplacement/TextReplacementReader.swift`、`Sources/AppCore/MainModel.swift`、`MainModel+Actions.swift`、`Sources/AppUI/MainView.swift` | 任务 2 |
| `Sources/RimeKit/Deploy/BackupStore.swift`、`Deployer.swift`、`Sources/RimeKit/AppPaths.swift` | 任务 3 |
| `Sources/RimeKit/Transfer/Importer.swift`、`Exporter.swift`、`Sources/RimeKit/UserDB/UserDBTransfer.swift`、`Sources/RimeKit/Deploy/SquirrelControl.swift`、`Sources/RimeKit/Packages/Unzipper.swift` | 任务 4 |
| `Sources/RimeKit/Net/HTTPClient.swift`、`Deploy/ApplyLock.swift`、`Deploy/Deployer.swift`、新 `Sources/RimeKit/Support/TextFile.swift` 及读文件的几处 | 任务 5 |
| `Sources/RimeKit/Takeover/TakeoverAnalyzer.swift` | 任务 6 |
| `Sources/RimeKit/Install/SquirrelInstaller.swift`、`Packages/PackageStore.swift` | 任务 7 |
| `Sources/RimeKit/AppInfo.swift`、`tools/release/build-release.sh`、`tools/vm/install-app.sh`、`Deploy/SquirrelControl.swift`、`docs/verified-facts.md` | 任务 8 |
| 测试：`Tests/RimeKitTests/` 下对应的测试文件；`Support/DeployFakes.swift` 加两个可以出错的开关 | 各任务 |

---

### Task 1: 第一次打开的引导（#2、#10、#14、#16、#22、#30、#35、#59）

**Files:**
- Modify: `Sources/AppCore/SetupFlow.swift`、`Sources/AppCore/AppState.swift`、`Sources/AppUI/RootView.swift`、`Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`、`Sources/RimeKit/Install/SquirrelActivator.swift`、`Sources/RimeKit/Install/PrivilegedInstaller.swift`
- Test: `Tests/RimeKitTests/SetupFlowTests.swift`、`AppStateTests.swift`、`SquirrelActivatorTests.swift`、`OsascriptInstallerTests.swift`

**Interfaces:**
- Produces:
  - `SetupFlow.Step.needInstall(String?)`：原来是 `.needInstall`；
  - `SetupFlow.reopenSettings()`；
  - `SquirrelActivator.activate(onRegistering:onWaiting:onLaunching:)`；
  - `AppState.launch(_ make: () throws -> AppEnvironment) -> (state: AppState?, error: String?)`；
  - `RootView(state:launchError:)`。

- [ ] **Step 1: 写会失败的测试**

`SetupFlowTests.swift` 里改两处、加四个：

```swift
    // 改：没装鼠须管时先装 —— `#expect(flow.step == .needInstall)` 换成
        #expect(flow.step == .needInstall(nil))

    // 改：取消授权时说清楚 —— 整个换成
    @Test func 取消授权时回到安装那一步_说清楚() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try FileManager.default.removeItem(at: m.locations.squirrelApp)
        let flow = SetupFlow(env: m.environment(install: { throw InstallError.cancelled }))
        await flow.start()
        await flow.install()
        guard case .needInstall(let note?) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(note.contains("取消"))
    }

    @Test func 安装失败的提示不重复前缀() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try FileManager.default.removeItem(at: m.locations.squirrelApp)
        let flow = SetupFlow(env: m.environment(install: { throw InstallError.installerFailed("磁盘满了") }))
        await flow.install()
        #expect(flow.step == .failed("安装鼠须管失败：磁盘满了"))
    }

    @Test func 读不了文本替换时提示去隐私与安全性() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        try F.wubiSample(m.packages, into: m.locations.rimeDirectory)
        struct Unreadable: Error, CustomStringConvertible { var description: String { "没有权限" } }
        let flow = SetupFlow(env: m.environment(textReplacements: { throw Unreadable() }))
        await flow.start()
        guard case .chooseStart(.existing(let summary)) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(summary.blockedReason?.contains("隐私与安全性") == true)
        #expect(summary.blockedReason?.contains("重新检查") == true)
    }

    @Test func 中途失败后_下载失败的提醒不留到下一次() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        final class Switch: @unchecked Sendable { var on = true }
        let offline = Switch()
        let failing = Switch()
        struct SwitchCompiler: RimeCompiler {
            let failing: Switch
            func compile(_ directory: URL) throws -> CompileReport {
                CompileReport(succeeded: !failing.on, errors: failing.on ? ["E20261015 boom"] : [])
            }
        }
        var env = m.environment()
        let fetch = env.fetchPackage
        env.fetchPackage = { spec in
            if offline.on { throw HTTPError.transport("断网了") }
            return try await fetch(spec)
        }
        env.compiler = SwitchCompiler(failing: failing)
        let flow = SetupFlow(env: env)
        await flow.useSettings(Settings(schemas: ["py"]))   // 下载失败用了旧版本，然后编译失败
        guard case .failed = flow.step else { Issue.record("\(flow.step)"); return }
        offline.on = false
        failing.on = false
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .done(let lines) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(!lines.contains { $0.contains("没下载成") })
    }

    @Test func 等添加输入法时可以重新打开系统设置() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let input = FakeInputSource(InputSourceState(registered: true, enabled: false, selected: false))
        let flow = SetupFlow(env: m.environment(input: input))
        flow.reopenSettings()
        #expect(input.calls == ["open"])
    }
```

说明：
- `env.compiler` 是 `AppEnvironment` 里放编译器的属性。名字不一样时按实际的名字改，在账本里记一条 Ruling。
- 如果 `RimeCompiler` 协议要求 `Sendable`，`SwitchCompiler` 里的 `Switch` 已经是 `@unchecked Sendable`，可以直接用。

`AppStateTests.swift` 加：

```swift
    @Test func 打开应用时出错_说出真实原因() {
        struct Broken: Error, CustomStringConvertible { var description: String { "方案清单坏了" } }
        let launch = AppState.launch { throw Broken() }
        #expect(launch.state == nil)
        #expect(launch.error?.contains("方案清单坏了") == true)
    }
```

`SquirrelActivatorTests.swift` 加（照这个文件里已有测试的写法建 activator；`env`、`activator` 等名字以文件里实际的为准）：

```swift
    @Test func 启动鼠须管前告诉界面() async throws {
        // 加好输入法后还要启动鼠须管、等第一次部署（最长两分钟），界面要换成「正在启动」
        let e = try env(state: InputSourceState(registered: true, enabled: true, selected: true), running: false)
        defer { e.dir.remove() }
        final class Flag: @unchecked Sendable { var called = false }
        let flag = Flag()
        _ = try await e.activator.activate(onLaunching: { flag.called = true })
        #expect(flag.called)
    }
```

`OsascriptInstallerTests.swift` 加：

```swift
    @Test func 授权没通过时说中文() {
        let denied = OsascriptPrivilegedInstaller.error(stderr: "0:139: execution error: The administrator user name or password was incorrect. (-60005)\n")
        #expect(denied.description.contains("密码不对"))
        let noUI = OsascriptPrivilegedInstaller.error(stderr: "0:139: execution error: blah (-60007)\n")
        #expect(noUI.description.contains("弹不出"))
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "SetupFlowTests|AppStateTests|SquirrelActivatorTests|OsascriptInstallerTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected: 编译错误（`needInstall(nil)`、`reopenSettings`、`AppState.launch`、`onLaunching` 都还没有），或者断言失败。

- [ ] **Step 3: 实现**

`SquirrelActivator.swift`：
- `activate` 加参数 `onLaunching: @Sendable () -> Void = {}`；
- 在 `try squirrel.launch()` 前调用 `onLaunching()`；
- 文档注释加一行：「onLaunching：要启动鼠须管、等它第一次部署时调用一次（界面上换成「正在启动」）」。

`PrivilegedInstaller.swift` 的 `PrivilegedInstallScript.error(status:message:)` 在 `default` 前加：

```swift
        // 系统授权框的错误号（osascript 原样带出英文消息）
        case -60005: return .installerFailed("授权没通过：密码不对，或者这个账户不是管理员")
        case -60007: return .installerFailed("现在弹不出系统授权框，请在已经登录的桌面里操作")
```

同一个文件第 85 行附近 `AuthorizationPromptInstaller` 的注释改成「rimectl --gui-auth 用（应用里用的是下面的 OsascriptPrivilegedInstaller）」。这一处也是 #70。

`SetupFlow.swift`：
- `Step` 里 `case needInstall` 改成 `case needInstall(String?)`，注释写「附带说明（例如取消了授权）」；`start()` 里写 `.needInstall(nil)`。
- `install()`：

```swift
        } catch InstallError.cancelled {
            step = .needInstall("你取消了授权，鼠须管没有安装。准备好了再点「安装鼠须管」")
        } catch let error as InstallError {
            step = .failed(error.description)   // 已经带「安装鼠须管失败：」
        } catch {
            step = .failed("安装鼠须管失败：\(Self.failure(error))")
        }
```

- `addInputMethod()`：

```swift
            switch try await offMain({ try await activator.activate(onLaunching: { [weak self] in
                Task { @MainActor in self?.step = .working("已经添加好了。正在启动鼠须管，第一次部署要等一会儿……") }
            }) }) {
```

- 新方法。它不受 `busy` 限制，因为等添加输入法时 `busy` 是真：

```swift
    /// 等添加输入法时：再打开一次系统设置（用户不小心关掉了）
    public func reopenSettings() {
        try? env.inputSource.openKeyboardSettings()
    }
```

- `prepareStart()` 里读不了文本替换时的那句改成：
  `blocked = "读不了 macOS 文本替换（\(error)），分不出哪些短语来自文本替换，暂时不能接管。可以去「系统设置 → 隐私与安全性」检查权限，然后点「重新检查」"`
- `fallbackNotes = []` 加在 `start()`、`useSettings(_:)`、`importFile(_:)` 里，放在 `busy = true` 那一行之后。不加在 `confirmTakeover()`：接管用的就是预览时取的包，那时的提醒要留着。

`AppState.swift` 加：

```swift
    /// 打开应用时建 AppState；建不了时（例如方案清单坏了）返回原因，界面上显示
    public static func launch(_ make: () throws -> AppEnvironment) -> (state: AppState?, error: String?) {
        do {
            return (AppState(env: try make()), nil)
        } catch {
            return (nil, "\(error)")
        }
    }
```

`SquirrelMacOSApp.swift`：

```swift
    @State private var launch = AppState.launch { try AppEnvironment.live() }
    …
            RootView(state: launch.state, launchError: launch.error)
```

`RootView.swift`：
- `RootView` 加 `let launchError: String?`，`init(state:launchError:)`。
- 没有 state 时，`lines` 改成 `[launchError ?? "未知原因", "应用好像坏了，请重新下载"]`，标题改成「应用打不开」。
- `.needInstall` 改成 `case .needInstall(let note):`，在 `Message` 后面加 `if let note { Note(text: note) }`。
- `.waitingForInputMethod`：在 `Working(...)` 下面加 `Button("重新打开系统设置") { flow.reopenSettings() }`。
- 接管页（`.existing`）：
  - `!summary.canConfirm` 时在按钮行加 `Button("重新检查") { Task { await flow.start() } }`；
  - 「改用起步方案」菜单里的按钮改成先设 `@State private var pendingStarter: Starter?`，再用 `.confirmationDialog` 确认：

```swift
        .confirmationDialog("改用起步方案？", isPresented: Binding(get: { pendingStarter != nil }, set: { if !$0 { pendingStarter = nil } }),
                            titleVisibility: .visible, presenting: pendingStarter) { starter in
            Button("改用「\(starter.displayName)」") { Task { await flow.useSettings(.starter(starter)) } }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("认出来的个人词库、短语不会带过去。原来的文件会先完整备份（这份备份永久保留）。")
        }
```

`.confirmationDialog` 挂在 `SetupView` 的 `ScrollView` 上，和 `.fileImporter` 并列。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "SetupFlowTests|AppStateTests|SquirrelActivatorTests|OsascriptInstallerTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -3`，再跑 `swift build`（视图要能编译）。

Expected: 全部通过，编译成功。

- [ ] **Step 5: 跑全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "fix(app): 引导里取消授权、输错密码、等部署时的说法和按钮；打开失败说原因；改用起步方案先确认

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 主窗口（#1、#71、#74、#75、#77）

**Files:**
- Modify: `Sources/RimeKit/TextReplacement/TextReplacementReader.swift`、`Sources/AppCore/MainModel.swift`、`Sources/AppCore/MainModel+Actions.swift`、`Sources/AppUI/MainView.swift`
- Test: `Tests/RimeKitTests/TextReplacementReaderTests.swift`、`MainModelTests.swift`、`MainModelActionsTests.swift`

**Interfaces:**
- Produces:
  - `MainModel.dismissExternalChanges()`；
  - `MainModel.reloadSettingsAfterImport() -> String?`（返回读不了时的提醒）。

- [ ] **Step 1: 写会失败的测试**

`TextReplacementReaderTests.swift`：

```swift
    @Test func 快捷码只差大小写的同一条只算一次() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try TextReplacementFixtures.makeDatabase(db, [("ABC", "同一条", 0), ("abc", "同一条", 0), ("abc", "另一条", 0)])
        let snapshot = try TextReplacementReader(database: db).snapshot()
        #expect(snapshot.usable.count == 2)
    }
```

`snapshot()` 的名字以 `TextReplacementReader` 里实际的为准，`read()` 也行。

`MainModelTests.swift`：

```swift
    @Test func 选项改回默认值不算有改动() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try SettingsStore(paths: m.paths).save(Settings(schemas: ["wb_py", "py"]))   // 没有写选项：都是默认值
        let model = try MainModel(env: m.environment())
        let wubi = model.optionPackages[0]
        let option = wubi.options[0]
        let other = try #require(option.choices.first { $0.id != option.defaultChoice })
        model.setChoice(other.id, option: option, of: wubi)
        #expect(model.isDirty)
        model.setChoice(option.defaultChoice, option: option, of: wubi)
        #expect(!model.isDirty)
    }
```

`MainModelActionsTests.swift`：

```swift
    @Test func 同步开着读不了文本替换时_说可以先关同步() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        struct Unreadable: Error, CustomStringConvertible { var description: String { "没有权限" } }
        let model = try MainModel(env: m.environment(textReplacements: { throw Unreadable() }))
        model.draft.textReplacement.sync = true
        await model.apply()
        #expect(model.notice?.title == "读不了 macOS 文本替换，没有写入")
        #expect(model.notice?.lines.contains { $0.contains("关掉同步") } == true)
    }

    @Test func 只有目录在Rime外面的改动时_不问覆盖_直接说不能写() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try SettingsStore(paths: m.paths).save(Settings(schemas: ["wb"]))   // 五笔要写 cn/a.dict.yaml
        let fm = FileManager.default
        try fm.createDirectory(at: m.locations.rimeDirectory, withIntermediateDirectories: true)
        let outside = m.dir.url.appending(path: "dotfiles/cn", directoryHint: .isDirectory)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: m.locations.rimeDirectory.appending(path: "cn"), withDestinationURL: outside)
        let model = try MainModel(env: m.environment())
        await model.apply()
        #expect(model.pendingExternalChanges == nil)
        #expect(model.notice?.title == "这些文件不能写，没有写入")
    }

    @Test func 关掉外部改动弹窗等于放弃() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        try Data("# 外面改的\n".utf8).write(to: m.locations.rimeDirectory.appending(path: "squirrel.custom.yaml"))
        model.draft.appearance.fontPoint = 30
        await model.apply()
        #expect(model.pendingExternalChanges != nil)
        model.dismissExternalChanges()
        #expect(model.pendingExternalChanges == nil)
        #expect(model.isDirty)   // 草稿还在
    }

    @Test func 导入后读不了设置时_说导入好了但要重开() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        try Data("坏了".utf8).write(to: m.paths.settingsFile)
        let note = try #require(model.reloadSettingsAfterImport())
        #expect(note.contains("导入好了"))
        #expect(note.contains("退出应用再打开"))
    }
```

说明：
- 如果 `T.machine()` 的五笔包写的不是 `cn/a.dict.yaml`，按 `DeploySymlinkTests.不能穿过指向外面的目录链接写文件` 的做法换成实际会写的目录，在账本里记一条 Ruling。
- 「关掉外部改动弹窗」这个测试改的文件名，按实际由应用写的文件换。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "TextReplacementReaderTests|MainModelTests|MainModelActionsTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected: 编译错误（`dismissExternalChanges`、`reloadSettingsAfterImport` 还没有），或者断言失败。

- [ ] **Step 3: 实现**

`TextReplacementReader.swift`：在 `usable.append(phrase)` 前去重。

```swift
            // 快捷码转小写后，只差大小写的同一条只留一条（生成短语时也只算一条）
            guard seen.insert(phrase.text + "\t" + phrase.code).inserted else { continue }
```

在循环前声明 `var seen = Set<String>()`。

`MainModel.swift`：`isDirty` 改成比较「去掉默认值的选项」后的设置。

```swift
    public var isDirty: Bool { normalized(draft) != normalized(saved) }

    /// 包选项里和默认值一样的项去掉（改回默认值不算改动）
    func normalized(_ settings: Settings) -> Settings {
        var copy = settings
        for (packageID, choices) in settings.options {
            guard let package = env.catalog.package(packageID) else { continue }
            let defaults = Dictionary(uniqueKeysWithValues: package.options.map { ($0.id, $0.defaultChoice) })
            let kept = choices.filter { defaults[$0.key] != $0.value }
            copy.options[packageID] = kept.isEmpty ? nil : kept
        }
        return copy
    }
```

`MainModel+Actions.swift`：
- `run(...)` 里 `let replacements = settings.textReplacement.sync ? try env.textReplacements().usable : []` 换成：

```swift
            let replacements: [Phrase]
            if settings.textReplacement.sync {
                do {
                    replacements = try env.textReplacements().usable
                } catch {
                    notice = Notice(kind: .error, title: "读不了 macOS 文本替换，没有写入",
                                    lines: ["\(error)", "可以去「系统设置 → 隐私与安全性」检查权限；或者先在「文本替换」页关掉同步，再应用改动"])
                    return
                }
            } else {
                replacements = []
            }
```

- `.externalChanges(let changes)` 分支：条件改成 `if options.overwriteExternalChanges || changes.allSatisfy({ if case .outsideRimeDirectory = $0 { true } else { false } })`。没法覆盖时直接说不能写，不弹窗。
- 新方法：

```swift
    /// 外部改动弹窗被关掉（按 Esc 等）：等于放弃这次改动，草稿留着
    public func dismissExternalChanges() {
        pendingExternalChanges = nil
    }

    /// 导入成功后重新读设置。读不了时返回提醒（导入本身已经成功）
    func reloadSettingsAfterImport() -> String? {
        do {
            if let now = try SettingsStore(paths: env.paths).load() {
                saved = now
                draft = now
            }
            return nil
        } catch {
            return "配置已经导入好了，但应用重新读设置时出错（\(error)）。请退出应用再打开"
        }
    }
```

- `importFile` 的 `.applied` 分支：`if let now = try SettingsStore…` 那 4 行换成 `if let note = reloadSettingsAfterImport() { lines.append(note) }`。

`MainView.swift`：`.confirmationDialog` 的 `set: { _ in }` 改成 `set: { if !$0 { model.dismissExternalChanges() } }`。

- [ ] **Step 4: 运行，确认通过；跑全部测试；提交**

```bash
swift test --filter "TextReplacementReaderTests|MainModelTests|MainModelActionsTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "fix(app): 主窗口：文本替换去重计数、读不了时建议关同步、外部改动弹窗、导入后读设置失败、选项改回默认值

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected：两次都全部通过。

---

### Task 3: 备份、还原、暂存区（#6、#52、#60）

**Files:**
- Modify: `Sources/RimeKit/Deploy/BackupStore.swift`、`Sources/RimeKit/Deploy/Deployer.swift`、`Sources/RimeKit/AppPaths.swift`、`Sources/AppCore/AppState.swift`
- Test: `Tests/RimeKitTests/BackupStoreTests.swift`、`DeployerRestoreTests.swift`、`AppPathsTests.swift`

**Interfaces:**
- Produces:
  - `BackupStore.prune(keep:protecting:)`；
  - `BackupError.createFailed(String)`；
  - `AppPaths.cleanStaleStaging(olderThan:now:)`。

- [ ] **Step 1: 写会失败的测试**

`BackupStoreTests.swift`：

```swift
    @Test func 备份失败时不留半截目录_报中文() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
        let file = rime.appending(path: "default.custom.yaml")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)   // 复制时读不了
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        #expect {
            try BackupStore(paths: paths).create(from: rime, reason: "测试", permanent: false, ledger: Ledger())
        } throws: { error in
            "\(error)".hasPrefix("备份失败")
        }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: paths.backups.path)) ?? []
        #expect(left.isEmpty, "\(left)")
    }
```

`DeployerRestoreTests.swift`（照文件里已有的 `env` 写法）：

```swift
    @Test func 还原最旧的那份后它不会被清理掉() async throws {
        let e = try DeployerTests().env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "patch: {}\n")
        // 先放 10 份旧的普通备份（时间从旧到新）
        var ids: [String] = []
        for day in 0..<10 {
            let store = BackupStore(paths: e.paths, now: { Date(timeIntervalSince1970: 1_000_000 + Double(day) * 86_400) })
            ids.append(try store.create(from: e.rime, reason: "应用改动前", permanent: false, ledger: Ledger()).id)
        }
        let oldest = ids[0]
        _ = try await e.deployer().restore(oldest)   // 还原前会再备份一份，一共 11 份普通备份
        #expect(BackupStore(paths: e.paths).info(oldest) != nil)
    }
```

`AppPathsTests.swift`：

```swift
    @Test func 打开应用时清理暂存区里的旧东西() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let fm = FileManager.default
        let old = paths.staging.appending(path: "fetch-old", directoryHint: .isDirectory)
        let fresh = paths.staging.appending(path: "fetch-new", directoryHint: .isDirectory)
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        let now = Date()
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-7_200)], ofItemAtPath: old.path)
        paths.cleanStaleStaging(olderThan: 3_600, now: now)
        #expect(!fm.fileExists(atPath: old.path))
        #expect(fm.fileExists(atPath: fresh.path))
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "BackupStoreTests|DeployerRestoreTests|AppPathsTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected:
- 「还原最旧」断言失败：那份被删了；
- 「备份失败」失败：留下了 `.partial`，错误是英文；
- `cleanStaleStaging` 编译错误：还没有这个方法。

- [ ] **Step 3: 实现**

`BackupStore.swift`：
- `BackupError` 加 `case createFailed(String)`，说明「备份失败（没有写入任何东西）：\(message)」。
- `create`：创建 `partial` 后的部分包进 `do/catch`：

```swift
        do {
            … 原来从 createDirectory(filesDir) 到 moveItem 的代码 …
        } catch {
            try? fm.removeItem(at: partial)
            throw BackupError.createFailed(String(describing: error))
        }
```

- `prune(keep: Int = 10, protecting: Set<String> = [])`：`removable` 先过滤掉 `protecting` 里的 id。

`Deployer.swift`：`restore` 里的 `_ = try? backups.prune()` 改成 `_ = try? backups.prune(protecting: [id])`，注释写「刚还原的这份不清理」。`id` 是 `restore` 的参数名，以实际为准。

`AppPaths.swift`：

```swift
    /// 暂存区里只放临时文件。进程被杀会留下来：打开应用时删掉 olderThan 秒以前的（不碰正在跑的操作）
    public func cleanStaleStaging(olderThan seconds: TimeInterval = 3_600, now: Date = Date()) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: staging.path)) ?? []
        for name in names {
            let url = staging.appending(path: name)
            guard let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > seconds else { continue }
            try? fm.removeItem(at: url)
        }
    }
```

`AppState.swift`：`start()` 开头（`guard main == nil` 之后）加 `env.paths.cleanStaleStaging()`。

- [ ] **Step 4: 运行，确认通过；跑全部测试；提交**

```bash
swift test --filter "BackupStoreTests|DeployerRestoreTests|AppPathsTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "fix: 还原的那份备份不被清理；备份失败不留半截；打开应用时清理暂存区

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 导入导出（#27、#31、#37、#42、#44、#67）

**Files:**
- Modify: `Sources/RimeKit/Deploy/Deployer.swift`（`ApplyOptions`）、`Sources/RimeKit/Transfer/Importer.swift`、`Sources/RimeKit/Transfer/Exporter.swift`、`Sources/RimeKit/UserDB/UserDBTransfer.swift`、`Sources/RimeKit/Deploy/SquirrelControl.swift`、`Sources/RimeKit/Packages/Unzipper.swift`、`docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（6.4 一句）
- Test: `Tests/RimeKitTests/ImporterTests.swift`、`UserDBTransferTests.swift`、`UnzipperTests.swift`（没有就新建）、`SquirrelControlTests.swift`（没有就新建）、`Support/DeployFakes.swift`

**Interfaces:**
- Produces:
  - `ApplyOptions.backupReason: String?`（普通备份的说明）；
  - `UserDBTransfer.exportAll/importAll` 返回 `UserDBResult { names: [String]; warning: String? }`；
  - `ImportReport.warnings: [String]`；
  - `Unzipper(maxBytes:)`；
  - `UnzipError.tooLarge(Int64)`；
  - `SquirrelControl.quitFailed(status:stderr:) -> Bool`。

- [ ] **Step 1: 测试辅助**

`Support/DeployFakes.swift` 的 `FakeSquirrel` 加两个开关：

```swift
    /// 不为空时 launch / reload 抛这个错（模拟通知鼠须管失败）
    var launchError: SquirrelError?
    var reloadError: SquirrelError?
```

- `reload()` 里记完 log 后加 `if let reloadError { throw reloadError }`；
- `launch()` 里记完 log、设 `running` 后加 `if let launchError { throw launchError }`；
- 两处都放在 `simulateDeploy()` 前。

- [ ] **Step 2: 写会失败的测试**

`ImporterTests.swift`：

```swift
    @Test func 已经由应用管理时_导入前的备份是普通的() async throws {
        let b = try T.machine(); defer { b.dir.remove() }
        _ = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied(let applied) = report.outcome else { Issue.record("没有写入"); return }
        #expect(!applied.backup.permanent)
        #expect(applied.backup.reason == "导入前")
    }

    @Test func 另存的导入前文件只留最近10个_同一秒也不覆盖() async throws {
        let b = try T.machine(); defer { b.dir.remove() }
        let fm = FileManager.default
        try fm.createDirectory(at: b.paths.beforeImport, withIntermediateDirectories: true)
        for i in 0..<12 {
            let old = b.paths.beforeImport.appending(path: "2020010\(i % 10)-00000\(i).zip")
            try Data("旧".utf8).write(to: old)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1_000 + i))], ofItemAtPath: old.path)
        }
        // importer(b) 的 now 是固定的：两次导入在「同一秒」
        let first = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        let second = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        #expect(first.previous != second.previous)
        let left = try fm.contentsOfDirectory(atPath: b.paths.beforeImport.path)
        #expect(left.count == 10)
        #expect(left.contains(try #require(second.previous).lastPathComponent))
    }

    @Test func 部署没完成时不合并输入习惯() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        b.squirrel.reloadError = .commandFailed("reload", "测试")   // 通知失败：看不到部署完成
        b.squirrel.launchError = .commandFailed("open", "测试")
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        #expect(report.mergedUserDB.isEmpty)
        #expect(report.userDBError?.contains("部署") == true)
    }
```

说明：
- `SquirrelError.commandFailed` 的参数以实际为准。
- 机器原来是「运行中」时走 reload，否则走 launch，所以两个开关都打开。

`UserDBTransferTests.swift`：

```swift
    @Test func 合并好了_最后启动鼠须管失败只是提醒() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "a.userdb.txt")
        try Data("新的\n".utf8).write(to: file)
        let tool = FakeUserDBTool(dbs: ["a": "旧的\n"])
        let s = try squirrel(dir, running: false)
        s.launchError = .commandFailed("open", "测试")
        let result = try await transfer(tool, s).importAll(["a": file])
        #expect(result.names == ["a"])
        #expect(result.warning?.contains("启动鼠须管") == true)
    }
```

这个文件里已有的 `== ["a", "b"]`、`== ["a"]` 改成 `.names == …`。

`UnzipperTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct UnzipperTests {
    @Test func 解开后太大的不解压() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let content = dir.url.appending(path: "c", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 10_000).write(to: content.appending(path: "big.txt"))
        let zip = dir.url.appending(path: "x.zip")
        try Zipper().zip(content, to: zip)
        #expect(throws: UnzipError.self) {
            try Unzipper(maxBytes: 1_000).unzip(zip, into: dir.url.appending(path: "out"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.url.appending(path: "out/big.txt").path))
        try Unzipper(maxBytes: 100_000).unzip(zip, into: dir.url.appending(path: "ok"))   // 没超就照常解
    }
}
```

`SquirrelControlTests.swift`：

```swift
import Testing
@testable import RimeKit

@Suite struct SquirrelControlTests {
    @Test func 退出鼠须管时只把没在运行当成正常() {
        #expect(!SquirrelControl.quitFailed(status: 0, stderr: ""))
        #expect(!SquirrelControl.quitFailed(status: 1, stderr: "No matching processes belonging to you were found\n"))
        #expect(SquirrelControl.quitFailed(status: 1, stderr: "killall: permission denied\n"))
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter "ImporterTests|UserDBTransferTests|UnzipperTests|SquirrelControlTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected：编译错误（`launchError`、`.names`、`maxBytes`、`quitFailed` 还没有），或者断言失败。

- [ ] **Step 4: 实现**

`Deployer.swift`：
- `ApplyOptions` 加 `public var backupReason: String?`，注释写「普通备份的说明（不为空时代替「应用改动前」）」，`init` 加同名参数，默认 nil。
- 备份那段的 `else` 分支：`reason = options.backupReason ?? (first ? "第一次应用前" : "应用改动前")`。

`Importer.swift`：
- 第 1 步另存：

```swift
            let file = Self.uniqueFile(in: paths.beforeImport, stamp: Self.stamp(now()))
            …
            Self.pruneBeforeImport(paths.beforeImport, keep: 10, protecting: file)
```

```swift
    /// 同一秒导入两次时加后缀，不覆盖
    static func uniqueFile(in dir: URL, stamp: String) -> URL {
        var file = dir.appending(path: "\(stamp).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = dir.appending(path: "\(stamp)-\(n).zip")
            n += 1
        }
        return file
    }

    /// 另存的导入前文件只留最近 keep 个（按修改时间），刚写的这个一定留着
    static func pruneBeforeImport(_ dir: URL, keep: Int, protecting: URL) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".zip") }) ?? []
        let dated = names.map { name -> (String, Date) in
            let date = (try? fm.attributesOfItem(atPath: dir.appending(path: name).path))?[.modificationDate] as? Date ?? .distantPast
            return (name, date)
        }.sorted { $0.1 > $1.1 }
        for (name, _) in dated.dropFirst(keep) where name != protecting.lastPathComponent {
            try? fm.removeItem(at: dir.appending(path: name))
        }
    }
```

- 第 2 步：

```swift
        // 应用还没管过 Rime 目录时（账本是空的），原来的配置不是应用写的：备份永久保留（设计 6.4）；
        // 已经由应用管理时，普通备份就够了，跟着最近 10 份轮换
        let firstTime = try Ledger.load(paths).entries.isEmpty
        let options = firstTime
            ? ApplyOptions(overwriteExternalChanges: true, permanentBackupReason: "导入前")
            : ApplyOptions(overwriteExternalChanges: true, backupReason: "导入前")
```

- 第 3 步：

```swift
        guard case .applied(let applied) = outcome, let userDB, !archive.userDB.isEmpty else { … 原来的 return … }
        guard applied.deploy.finished else {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], warnings: [],
                                userDBError: "等了很久还没看到鼠须管部署完成，输入习惯先没合并。部署好以后再导入一次这个文件就行（配置不会重复）")
        }
```

  合并成功时 `warnings: result.warning.map { [$0] } ?? []`。

- `ImportReport` 加 `public let warnings: [String]`。所有构造处都补上，没有提醒的写 `[]`。

`UserDBTransfer.swift`：

```swift
public struct UserDBResult: Sendable, Equatable {
    public let names: [String]
    /// 导出、合并都做完了，只是最后重新启动鼠须管失败：提醒用户自己切换一下输入法
    public let warning: String?
}
```

- `exportAll`、`importAll` 返回 `UserDBResult`。
- 最后的 `try squirrel.launch()` 换成：

```swift
        do {
            try squirrel.launch()
        } catch {
            return UserDBResult(names: names, warning: "重新启动鼠须管失败（\(error)）：切换一下输入法，或者从「应用程序」里打开鼠须管")
        }
        return UserDBResult(names: names, warning: nil)
```

  其中 `exportAll` 只在 `wasRunning` 时启动。

`Exporter.swift`：`let userDBNames = try await userDB?.exportAll(…) ?? []` 改成先取 `result`，`userDBNames = result?.names ?? []`，`result?.warning` 加进 `warnings`。

`MainModel+Actions.swift` 的 `importFile`：`lines += report.warnings`。`SetupFlow.importFile` 也一样：`notes += report.warnings`。

`SquirrelControl.swift`：

```swift
    public func quit() throws {
        let r = try Shell.run("/usr/bin/killall", ["-u", NSUserName(), "Squirrel"])
        if Self.quitFailed(status: r.status, stderr: r.stderr) {
            throw SquirrelError.commandFailed("退出鼠须管", r.stderr)
        }
    }

    /// killall 没找到进程时返回 1（鼠须管本来就没在运行），这不算失败
    static func quitFailed(status: Int32, stderr: String) -> Bool {
        status != 0 && !stderr.contains("No matching processes")
    }
```

`Unzipper.swift`：

```swift
    /// 解开后的总大小上限（设计第 7 节：坏的或者意外的大文件不要塞满磁盘）
    let maxBytes: Int64

    public init(maxBytes: Int64 = 2_000_000_000) {
        self.maxBytes = maxBytes
    }

    public func unzip(_ zip: URL, into directory: URL) throws {
        let size = try Self.uncompressedSize(zip)
        guard size <= maxBytes else { throw UnzipError.tooLarge(size) }
        … 原来的 ditto 解压 …
    }

    /// zipinfo -t 的最后一行：「N files, X bytes uncompressed, Y bytes compressed: Z%」
    static func uncompressedSize(_ zip: URL) throws -> Int64 {
        let r = try Shell.run("/usr/bin/zipinfo", ["-t", zip.path])
        guard r.status == 0, let range = r.stdout.range(of: #"(\d+) bytes uncompressed"#, options: .regularExpression),
              let size = Int64(r.stdout[range].split(separator: " ")[0]) else {
            throw UnzipError.failed(status: r.status, message: "看不出 zip 解开后有多大：\(r.stderr)")
        }
        return size
    }
```

`UnzipError` 加 `case tooLarge(Int64)`，说明「这个文件解开后有 \(size / 1_000_000) MB，太大了，没有解开（可能文件坏了）」。

设计 6.4：第 286 行「先完整备份（永久保留）再导入」后面加「（应用还没管过 Rime 目录时；已经由应用管理时是普通备份）」。第 291 行同样补一句。

- [ ] **Step 5: 运行，确认通过；跑全部测试；提交**

```bash
swift test --filter "ImporterTests|UserDBTransferTests|UnzipperTests|SquirrelControlTests|ExporterTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests docs/superpowers/specs
git commit -m "fix: 导入不再每次加永久备份、另存文件只留 10 个；部署没完不合并；最后启动失败只提醒；解压限大小；退出鼠须管看结果

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 出错提示（#3、#5、#7、#46）

**Files:**
- Create: `Sources/RimeKit/Support/TextFile.swift`
- Modify: `Sources/RimeKit/Net/HTTPClient.swift`、`Sources/RimeKit/Deploy/ApplyLock.swift`、`Sources/RimeKit/Deploy/Deployer.swift`
  - 读文件的几处：`Sources/RimeKit/Takeover/TakeoverFiles.swift:10`、`Sources/RimeKit/Config/GenerationContext.swift:57,249`、`Sources/RimeKit/Config/Personal.swift:75`、`Sources/RimeKit/Takeover/TakeoverAnalyzer.swift:119,140`
- Test: `Tests/RimeKitTests/HTTPClientTests.swift`（没有就新建）、`ApplyLockTests.swift`（没有就新建）、`DeployerTests.swift`、`TextFileTests.swift`（新建）

**Interfaces:**
- Produces:
  - `TextFile.read(_ url: URL) throws -> String`；
  - `TextFileError.notUTF8(String)`；
  - `ApplyError.lockFailed(String)`。

- [ ] **Step 1: 写会失败的测试**

```swift
// HTTPClientTests.swift
    @Test func 请求太频繁时说过一会儿再试() {
        #expect(HTTPError.status(429, URL(string: "https://example.com")!).description.contains("过一会儿再试"))
    }

// ApplyLockTests.swift
    @Test func 打不开锁文件时不说正在应用() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.lockFile, withIntermediateDirectories: true)   // 锁文件的位置是个目录：打不开
        #expect {
            _ = try ApplyLock.acquire(paths)
        } throws: { error in
            "\(error)".contains("锁文件") && !"\(error)".contains("正在应用")
        }
    }

// DeployerTests.swift
    @Test func 通知鼠须管失败时不再等部署() async throws {
        let e = try env(running: true); defer { e.dir.remove() }
        e.squirrel.reloadError = .commandFailed("reload", "测试")
        final class Count: @unchecked Sendable { var n = 0 }
        let sleeps = Count()
        let watcher = DeployWatcher(locations: e.locations, pollInterval: .milliseconds(1), timeout: .seconds(120),
                                    sleep: { _ in sleeps.n += 1 })
        let deployer = Deployer(paths: e.paths, locations: e.locations, compiler: FakeCompiler(), squirrel: e.squirrel,
                                watcher: watcher, now: { Date(timeIntervalSince1970: 1_000) })
        let report = try applied(try await deployer.apply(try e.input(Settings(schemas: ["wb"])), options: ApplyOptions()))
        #expect(report.warnings.contains { $0.contains("通知鼠须管失败") })
        #expect(!report.deploy.finished)
        #expect(sleeps.n == 0)
    }

// TextFileTests.swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TextFileTests {
    @Test func 不是UTF8时说是哪个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "custom_phrase.txt")
        try Data([0xC4, 0xE3, 0xBA, 0xC3]).write(to: file)   // GBK 的「你好」
        #expect {
            _ = try TextFile.read(file)
        } throws: { error in
            "\(error)".contains("custom_phrase.txt") && "\(error)".contains("UTF-8")
        }
    }
}
```

`Deployer` 的构造参数、`applied(_:)`、`e.input(_:)` 以 `DeployerTests` 里实际的为准。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "HTTPClientTests|ApplyLockTests|DeployerTests|TextFileTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected：编译错误（`TextFile` 还没有），或者断言失败（429 的说明、锁文件、等了 sleep）。

- [ ] **Step 3: 实现**

`HTTPClient.swift` 的 `description` 加：

```swift
        case .status(429, let url):
            return "请求太频繁（429），请过一会儿再试：\(url.absoluteString)"
```

`ApplyLock.swift`：
- `ApplyError` 加 `case lockFailed(String)`，说明「打不开锁文件 \(path)（可能没有权限或者磁盘满了）」。
- `guard fd >= 0 else { throw ApplyError.lockFailed(paths.lockFile.path) }`。

`Deployer.swift` 的 `notifySquirrel`：

```swift
        } catch {
            // 没通知到鼠须管就不会部署：不用再等两分钟
            return (launched, DeployOutcome(finished: false, errors: []), ["通知鼠须管失败：\(error)"])
        }
```

`Sources/RimeKit/Support/TextFile.swift`：

```swift
import Foundation

public enum TextFileError: Error, Equatable, Sendable, CustomStringConvertible {
    case notUTF8(String)

    public var description: String {
        switch self {
        case .notUTF8(let path):
            return "\((path as NSString).lastPathComponent) 不是 UTF-8 编码的文本，读不了。请用文本编辑器另存为 UTF-8 再试（\(path)）"
        }
    }
}

/// 读配置、短语这类文本文件：不是 UTF-8 时说清楚是哪个文件
public enum TextFile {
    public static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw TextFileError.notUTF8(url.path) }
        return text
    }
}
```

文件结构表里列的那几处，`String(contentsOf: X, encoding: .utf8)` 换成 `TextFile.read(X)`。只换读 Rime 目录、个人内容、上游包文件的地方。用 `grep -rn "contentsOf:.*encoding: .utf8" Sources/RimeKit` 找全，每处看一眼。测试工具和日志不换。

- [ ] **Step 4: 运行，确认通过；跑全部测试；提交**

```bash
swift test --filter "HTTPClientTests|ApplyLockTests|DeployerTests|TextFileTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "fix: 429、锁文件、非 UTF-8 文件的提示说清楚；通知鼠须管失败时不再干等

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 接管时的边角写法（#18、#39、#51、#57、#62、#65）

**Files:**
- Modify: `Sources/RimeKit/Takeover/TakeoverAnalyzer.swift`
- Test: `Tests/RimeKitTests/TakeoverAnalyzerTests.swift`

**Interfaces:**
- Consumes：`TakeoverFixtures` 的 `env`、`install`、`put`、`analyze`、`upstream`、`wubiSample`（已有）
- Produces：`TakeoverProposal.notes` 里多几类提醒；`preservedPatches` 不再包含应用管理的 `schema_list/+`、方案的 `menu/page_size`。

- [ ] **Step 1: 写会失败的测试**

```swift
    @Test func 追加方案和方案自己的每页候选数算应用管理的() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["pinyin"], from: e.packages, into: e.rime)
        try F.put("patch:\n  schema_list:\n    - schema: py\n  schema_list/+:\n    - schema: py\n", "default.custom.yaml", in: e.rime)
        try F.put("patch:\n  menu/page_size: 9\n", "py.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.preservedPatches["default"]?.map(\.key).contains("schema_list/+") != true)
        #expect(p.settings.preservedPatches["py"] == nil)
        #expect(p.notes.contains { $0.contains("py.custom.yaml") && $0.contains("每页候选数") })
    }

    @Test func 没用短语的方案不读残留的短语文件() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put("# Rime table\n别的方案的默认短语\tmrdy\t1\n", "custom_phrase.txt", in: e.rime)   // 残留的，五笔没有注入短语
        let p = try F.analyze(e)
        #expect(p.manualPhrases.isEmpty)
    }

    @Test func 认不出的写法在预览里提醒() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["pinyin"], from: e.packages, into: e.rime)
        try F.put("patch:\n  schema_list:\n    - schema: py\n      case: [mode/full]\n", "default.custom.yaml", in: e.rime)
        try F.put("__include: other.yaml\npatch:\n  app_options:\n", "squirrel.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.notes.contains { $0.contains("schema_list") && $0.contains("case") })
        #expect(p.notes.contains { $0.contains("squirrel.custom.yaml") && $0.contains("__include") })
        #expect(p.notes.contains { $0.contains("app_options") && $0.contains("空") })
    }

    @Test func 符号链接的配置文件在预览里提醒() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["pinyin"], from: e.packages, into: e.rime)
        let real = e.dir.url.appending(path: "dotfiles/default.custom.yaml")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("patch:\n  schema_list:\n    - schema: py\n".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: e.rime.appending(path: "default.custom.yaml"), withDestinationURL: real)
        let p = try F.analyze(e)
        #expect(p.notes.contains { $0.contains("default.custom.yaml") && $0.contains("符号链接") })
    }
```

说明：
- 包 id（`pinyin`、`wubi`）、方案 id（`py`）以 `TakeoverFixtures` 里实际的为准。
- 五笔的样例方案如果本来就有短语翻译器，把第二个测试换成一个没有短语翻译器的方案，在账本里记一条 Ruling。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TakeoverAnalyzerTests 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected：新加的 4 个失败，原来的都通过。

- [ ] **Step 3: 实现**（都在 `TakeoverAnalyzer.swift`）

- `managedPaths(_:)`：
  - `"default"` 加 `"schema_list/+"`；
  - `default:` 分支：如果 `name` 是认出的方案（`survey.schemas.contains(name)`），返回 `["menu/page_size"]`。
  - `preservedItems` 里跳过方案的 `menu/page_size` 时加提醒：「\(name).custom.yaml 里方案自己的每页候选数（menu/page_size）接管后改用应用里的设置」。只在这个方案的补丁里确实有这一项时加。
- `detectPhrases()`：方案的上游 translators 里没有短语翻译器时，只有用户补丁里注入了短语翻译器才去读短语文件。判断方法是 `existing[schema]` 的条目里有 `isPhraseInjection` 为真的。没有就 `continue`。
- 空值（#51）：`preservedItems` 里 `entry.value` 是 null 时，不保留，加提醒：「\(name).custom.yaml 里 \(entry.key) 的值是空的，接管后不保留」。
- schema_list 多余字段（#57）：读 `default.custom.yaml` 补丁的 `schema_list` 时，有条目带 `schema` 以外的键，就加提醒：「default.custom.yaml 的 schema_list 里有 schema 以外的写法（例如 case:），接管后不保留，方案顺序照旧」。
- `__patch` / `__include`（#65）：对每个 `*.custom.yaml`，用 `TakeoverFiles.yaml` 读顶层，有 `__patch` 或 `__include` 键，就加提醒：「\(file) 用了 __patch / __include，这个应用认不出，接管后不保留」。
- 符号链接（#62）：Rime 目录里是符号链接的配置文件，加提醒：「\(file) 是符号链接，接管后应用写的文件会换成普通文件（原来的链接在备份里）」。用 `(try? FileManager.default.destinationOfSymbolicLink(atPath:)) != nil` 判断。

提醒都放进 `notes`。这几处具体插在哪里，按 `TakeoverAnalyzer` 现有的结构定，放进各自已有的扫描循环里，不另开一遍扫描。

- [ ] **Step 4: 运行，确认通过；跑全部测试；提交**

```bash
swift test --filter "TakeoverAnalyzerTests|TakeoverApplierTests|TakeoverPreviewTests|SetupFlowTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "fix(takeover): 追加方案、方案自己的每页候选数算应用管理的；不读残留短语；认不出的写法在预览里提醒

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 下载鼠须管和方案包（#40、#47）

**Files:**
- Modify: `Sources/RimeKit/Install/SquirrelInstaller.swift`、`Sources/RimeKit/Packages/PackageStore.swift`
- Test: `Tests/RimeKitTests/SquirrelInstallerTests.swift`、`PackageStoreTests.swift`

- [ ] **Step 1: 写会失败的测试**

```swift
// SquirrelInstallerTests.swift
    @Test func 版本号不是纯数字时_相同就不重装() async throws {
        let e = try env(latest: "1.2.0-rc1", installed: "1.2.0-rc1"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .alreadyInstalled("1.2.0-rc1"))
    }

    @Test func 版本号不是纯数字时也能装_装完不报版本不对() async throws {
        let e = try env(latest: "1.2.0-rc1"); defer { e.dir.remove() }
        #expect(try await e.installer.install() == .installed("1.2.0-rc1", previous: nil))
        #expect(e.privileged.installedPackages == ["Squirrel.pkg"])
    }

// PackageStoreTests.swift
    @Test func 找包根目录按目录层数取最浅的() {
        #expect(PackageStore.locateRoot(in: ["abcdefgh/x.yaml", "a/b/x.yaml"], anchor: "x.yaml") == "abcdefgh/")
    }
```

`没装时下载检查安装` 里的 `["Squirrel-1.1.2.pkg"]` 改成 `["Squirrel.pkg"]`。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "SquirrelInstallerTests|PackageStoreTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head`

Expected：新加的 3 个和改过的那个失败。

- [ ] **Step 3: 实现**

`SquirrelInstaller.swift`：

```swift
        if !force, let current, Self.isUpToDate(current: current, latest: release.version) {
            return .alreadyInstalled(current)
        }
        …
        // 文件名固定：版本号里可能有 / 之类的字符
        let pkg = work.appending(path: "Squirrel.pkg")
        …
        guard let after, Self.sameVersion(after, release.version) else {
            throw InstallError.versionMismatch(expected: release.version, found: after)
        }
```

```swift
    /// 版本号都是数字时按数字比；认不出（rc、beta 等）时按原文比是否相同
    static func isUpToDate(current: String, latest: String) -> Bool {
        if let have = SquirrelVersion(current), let new = SquirrelVersion(latest) { return have >= new }
        return trimmed(current) == trimmed(latest)
    }

    static func sameVersion(_ a: String, _ b: String) -> Bool {
        if let x = SquirrelVersion(a), let y = SquirrelVersion(b) { return x == y }
        return trimmed(a) == trimmed(b)
    }

    static func trimmed(_ v: String) -> String { v.hasPrefix("v") ? String(v.dropFirst()) : v }
```

`PackageStore.swift` 的 `locateRoot`：`.min { $0.count < $1.count }` 改成 `.min { ($0.filter { $0 == "/" }.count, $0) < ($1.filter { $0 == "/" }.count, $1) }`，注释写「按目录层数取最浅的」。

- [ ] **Step 4: 运行，确认通过；跑全部测试；提交**

```bash
swift test --filter "SquirrelInstallerTests|PackageStoreTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "fix: 鼠须管版本号不是纯数字时不反复重装；安装包文件名固定；方案包根目录按层数找

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 开发工具和文档（#4、#20、#24、#36、#70、#72）

**Files:**
- Modify: `Sources/RimeKit/AppInfo.swift`、`Sources/RimeKit/Deploy/SquirrelControl.swift`、`tools/release/build-release.sh`、`tools/vm/install-app.sh`、`docs/verified-facts.md`、`docs/release.md`

- [ ] **Step 1: 改**

- #4：删掉 `AppInfo.englishName`。先 `grep -rn englishName Sources Tests`，确认没有地方用。
- #24：`SquirrelControl.swift` 里「输入源从系统里消失时用…」「重装不一定有用…」两行注释，挪到 `registerInputSource()` 上面。`quit()` 上只留它自己的注释。
- #36：`install-app.sh` 的删除命令改成 `rm -rf ~/Applications/SquirrelHelper.app ~/Applications/squirrel-macos.app ~/Applications/鼠须管助手.app`。
- #70：
  - `verified-facts.md` 第 30 行「进程里用 `NSAppleScript` 的 `with administrator privileges` 安装」改成「用 osascript 子进程执行 `do shell script … with administrator privileges` 安装（`OsascriptPrivilegedInstaller`）」；
  - 再加一句：「rimectl `--gui-auth` 用的进程内 `NSAppleScript` 在 hardened runtime 下没有验证过」。
  - `PrivilegedInstaller.swift` 的注释在任务 1 已改。
- #20：`build-release.sh` 在 `cd` 之后加：

```bash
# 发布包要和提交对得上：工作区有没提交的改动就不打包（试流程可以加 ALLOW_DIRTY=1）
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-}" != "1" ]; then
  echo "工作区有没提交的改动，先提交再打发布包（只是试流程的话加 ALLOW_DIRTY=1）" >&2
  exit 1
fi
echo "提交：$(git rev-parse --short HEAD)" >&2
```

- #72：公证那段改成：

```bash
  result="$(xcrun notarytool submit "$OUT/upload.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || true
  printf '%s\n' "$result" > "$OUT/notary.json"
  status="$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)"
  echo "公证结果：${status:-（没拿到）}（${id:-没有 id}）" >&2
  if [ "$status" != "Accepted" ]; then
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
    echo "公证没通过，完整结果在 $OUT/notary.json" >&2
    exit 1
  fi
```

- `docs/release.md` 第 4 步加一句：「工作区要干净（没提交的改动会被拒绝；试流程加 `ALLOW_DIRTY=1`）」。

- [ ] **Step 2: 检查**

```bash
grep -rn englishName Sources Tests || echo 已删
bash -n tools/release/build-release.sh && bash -n tools/vm/install-app.sh && echo 语法正确
(touch ./.dirty-check && SKIP_NOTARIZE=1 ./tools/release/build-release.sh; echo "exit=$?"; rm -f ./.dirty-check) 2>&1 | tail -2
swift test 2>&1 | grep -E "error:|Test run" | tail -2
```

Expected：
- 「已删」；
- 「语法正确」；
- 有没提交的文件时打印「工作区有没提交的改动…」，`exit=1`；
- 测试全部通过。

- [ ] **Step 3: 提交**

```bash
git add Sources tools docs/verified-facts.md docs/release.md
git commit -m "chore: 发布脚本检查工作区、公证失败留下结果；整理注释和测试机脚本

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 干净测试机里走一遍改过的流程

**Files:**
- Create: `docs/backlog-fixes-vm-log.md`

- [ ] **Step 1: 准备**

```bash
./tools/vm/vm.sh new squirrel-fix
```

请你登录桌面。然后：

```bash
./tools/vm/install-app.sh squirrel-fix
```

这是 debug 版，临时签名，用来看界面。

- [ ] **Step 2: 请你在测试机里操作（AskUserQuestion，一次问一组）**

1. 安装：
   - 点「安装鼠须管」，授权框里**先点取消**：应回到「第一步」，上面有「你取消了授权…」，不是出错页。
   - 再点安装，**故意输错密码三次**：应显示中文的「授权没通过：密码不对…」。
   - 再来一次，输对密码。
2. 添加输入法：
   - 到「添加输入法」，点「打开系统设置」后**把系统设置关掉**：等待页上应有「重新打开系统设置」按钮，点了能打开。
   - 加好鼠须管后，应显示「已经添加好了。正在启动鼠须管…」，然后到第三步。
3. 选「雾凇拼音（全拼）」，进主窗口：
   - 外观页把某个包选项改了再改回原来的值，底部的「有改动还没应用」应消失。如果没有包选项，就改方案的启用再改回来。

同时用 SSH 记录（不打印文本替换内容）：

```bash
./tools/vm/vm.sh ssh squirrel-fix 'ls ~/Library/Application\ Support/squirrel-macos/staging 2>/dev/null | wc -l; ls ~/Library/Application\ Support/squirrel-macos/backups'
```

- [ ] **Step 3: 接管页的「改用起步方案」确认**

```bash
./tools/vm/vm.sh ssh squirrel-fix 'pkill -x SquirrelMacOSApp; rm -rf ~/Library/Application\ Support/squirrel-macos; sudo launchctl asuser $(id -u) sudo -u tester open ~/Applications/SquirrelHelper.app'
```

应用会把 Rime 目录当成「已有配置」，显示接管预览。请你点「改用起步方案 → 雾凇拼音（全拼）」：
- 应先弹确认，说明认出的个人词库、短语不会带过去；
- 点「取消」什么都不变；
- 再点并确认，才写入。

- [ ] **Step 4: 写记录，删测试机，提交**

`docs/backlog-fixes-vm-log.md` 按以前实测记录的格式写：日期、每一步用户看到的（✅ / ❌）、结论。

```bash
tart stop squirrel-fix; tart delete squirrel-fix
git add docs/backlog-fixes-vm-log.md
git commit -m "docs: 待改进项修复的测试机实测记录

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 文档

**Files:**
- Modify: `docs/backlog.md`、`CLAUDE.md`、`docs/superpowers/plans/2026-10-15-roadmap.md`

- [ ] **Step 1: 改**

- `docs/backlog.md`：
  - 「本计划修」里每条的「处理」改成「已修（0.1.1）」；
  - 如果有哪条最后没修，写明原因，挪到「以后再说」；
  - 文件开头加一句「0.1.1 修了 40 条」。
- `CLAUDE.md` 第一段：「……第一版已发布 0.1.0（预发布）……；修了待改进项清单（`docs/backlog.md`）里应用用户会碰到的问题，准备出 0.1.1」。
- 路线图加一行：`| 修复 | 0.1.1 | 待改进项清单里应用用户会碰到的 34 条 + 开发工具 6 条（已完成，日期） | 宿主机单元测试 + 干净测试机里走一遍 |`

- [ ] **Step 2: 提交，推送**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add docs CLAUDE.md
git commit -m "docs: 待改进项清单标上已修，更新路线图和说明

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

---

### Task 11: 出 0.1.1（先问你）

**Files:**
- Create: `docs/release-notes/0.1.1.md`
- Modify: `tools/app/Info.plist`（`CFBundleShortVersionString` 改 `0.1.1`，`CFBundleVersion` 改 `2`）

- [ ] **Step 1: 改版本号，写说明，打包**

`docs/release-notes/0.1.1.md` 照 0.1.0 的格式写：
- 「修了 40 处小问题」，挑用户看得见的列 6 到 8 条：取消授权、输错密码、等部署时的说法，还原最旧的备份，导入不再多存永久备份，接管时的提醒，等等；
- 已知限制照抄 0.1.0。

提交版本号和说明后（发布脚本要求工作区干净），运行：

```bash
git add tools/app/Info.plist docs/release-notes/0.1.1.md
git commit -m "release: 0.1.1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
./tools/release/build-release.sh 2>.build/release-notarize.log | tail -1
grep -E "提交：|公证结果|The staple and validate action worked|source=|ok：" .build/release-notarize.log
```

公证要几分钟，用 `run_in_background` 跑。

Expected：
- `公证结果：Accepted`；
- `source=Notarized Developer ID`；
- `ok：…zip`。

把 sha256 写进 `docs/release-notes/0.1.1.md`，提交并推送。

- [ ] **Step 2: 问你（AskUserQuestion）**

列出要做的公开操作：
- 打 tag `v0.1.1` 并推送；
- 建 GitHub Release「鼠须管助手 0.1.1」，标成预发布，附 zip 和 `.sha256`。

你同意了再做。

- [ ] **Step 3: 发布、核对**

```bash
git tag v0.1.1 && git push origin v0.1.1
gh release create v0.1.1 .build/release-out/SquirrelHelper-0.1.1.zip .build/release-out/SquirrelHelper-0.1.1.zip.sha256 \
  --title "鼠须管助手 0.1.1" --notes-file docs/release-notes/0.1.1.md --prerelease -R pokoblin/squirrel-macos
rm -rf .build/release-check && mkdir -p .build/release-check && (cd .build/release-check && gh release download v0.1.1 -R pokoblin/squirrel-macos && shasum -a 256 -c SquirrelHelper-0.1.1.zip.sha256)
./tools/release/check-zip.sh .build/release-check/SquirrelHelper-0.1.1.zip
```

Expected：`OK`、`ok：…`，并得到 Release 的链接。
