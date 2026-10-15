# 发布包实测记录：鼠须管助手 0.1.0

- 日期：2026-10-15
- 测试机：新克隆的 `squirrel-release`（干净的 macOS 27.0.1，没装鼠须管；测完删掉）
- 计划：[2026-10-15-release-0.1.0.md](superpowers/plans/2026-10-15-release-0.1.0.md) 任务 5
- 发布包：`./tools/release/build-release.sh` 打出的 `SquirrelHelper-0.1.0.zip`（Developer ID 签名、hardened runtime、已公证、钉了票据）

## 怎么模拟「从浏览器下载」

把 zip 放进测试机的 `/Users/Shared`，再加上浏览器下载时会有的隔离标记：

```bash
./tools/vm/vm.sh ssh squirrel-release "xattr -w com.apple.quarantine \"0081;\$(printf %x \$(date +%s));Safari;\$(uuidgen)\" /Users/Shared/SquirrelHelper-0.1.0.zip"
```

用户在访达里双击 zip 解压后，解出来的应用也带着隔离标记，所以打开时 Gatekeeper 会真的检查。

注意：宿主机删掉再重建 `.build/release-out/` 后，测试机的共享文件夹有时一时看不到新文件。这时改用 SSH 传过去：`./tools/vm/vm.sh ssh 测试机 "cat > /Users/Shared/文件名" < 本地文件`。

## 1. 第一轮（应用名还只有中文）

| 步骤 | 用户看到的 | |
|---|---|---|
| 在 `/Users/Shared` 解压，不挪动，直接打开 | 只有系统的「是从互联网下载的，确定要打开吗」，点「打开」后到引导第一步「安装鼠须管」。没有「无法验证开发者」「已损坏」 | ✅ |
| 拖进「应用程序」再打开 | 同上 | ✅ |
| 安装鼠须管 | **弹出系统授权框**，输密码后装好（hardened runtime 没有拦 `NSAppleScript`） | ✅ |
| 添加输入法、选雾凇全拼 | 「设置好了」，备忘录里 `nihao` → 你好 | ✅ |
| 文本替换页 | 显示条数（系统自带 1 条），**没有报错，也没有弹窗要权限** | ✅ |
| 关于窗口 | 版本 0.1.0、版权那一行 | ✅ |

SSH 检查：`spctl` 显示 `accepted`、`source=Notarized Developer ID`；数据目录还是 `~/Library/Application Support/squirrel-macos`。

用户这一轮提了两处修改：
- 版权人改成 Pokoblin；
- 应用名跟系统语言走：中文系统显示「鼠须管助手」，其他语言显示 SquirrelHelper。

导出这一步用户没有点「存储」。用户又要求导出的默认文件名带上当前时间。

## 2. 第二轮（改完、重新公证后）

改动：
- `.app` 文件名改成 `SquirrelHelper.app`；
- `Info.plist` 写英文名，打开 `LSHasLocalizedDisplayName`；
- `en`、`zh-Hans`、`zh-Hant` 三个 `InfoPlist.strings`；
- 版权人改为 Pokoblin；
- 导出默认文件名改成「鼠须管助手 导出 年-月-日 时.分.秒.zip」。

删掉测试机里的旧应用（设置留着），放进新的 zip，同样加隔离标记。

| 步骤 | 用户看到的 | |
|---|---|---|
| 英文优先的系统里解压 | 访达显示 SquirrelHelper；拖进「应用程序」打开，只有「从互联网下载」的提示 | ✅ |
| 打开 | 直接进主窗口（设置还在）；窗口标题、菜单栏是 SquirrelHelper；「About SquirrelHelper」里版权是 Pokoblin | ✅ |
| 导出 | 默认文件名带当前时间；存到 `/Users/Shared`，显示「已导出」 | ✅ |
| 改成简体中文优先，注销再登录 | 访达里显示「鼠须管助手」；窗口标题、菜单栏、「关于鼠须管助手」都是中文名，版权是 Pokoblin | ✅ |

SSH 检查：`/Applications/SquirrelHelper.app` 是 `accepted`、`source=Notarized Developer ID`。

## 结论

- 公证过的发布包从「下载」开始走得通：Gatekeeper 不拦，安装鼠须管时的授权框照常弹出，不加 entitlement 也能读文本替换。结果写进了 [verified-facts.md](verified-facts.md)。
- 实测里用户提的三处修改都做了，第二轮复查通过。
- 测完删掉了 `squirrel-release`。
