# 阶段 0 验证记录

日期：2026-10-15。环境：Tart 测试机 `squirrel-dev`（从 `macos-base` 克隆，macOS 27.0.1），宿主机 macOS 27.0.1。

| # | 验证项 | 结论 | 详情 |
|---|---|---|---|
| 1 | 系统设置键盘页链接 | | |
| 2 | 授权弹窗安装时 postinstall 拿到桌面用户 | **能** | `osascript … with administrator privileges` 弹出系统授权框，输密码后安装成功（约 9 秒）。postinstall 以桌面用户身份注册、启用了 `Squirrel.Hans`，状态和 `sudo installer` 完全一样（本体仍 enabled=false，选中失败）。见「过程」 |
| 3 | 独立 .app 读文本替换数据库 | | |
| 4 | `ditto` 解压 GitHub zip | | |
| 5 | 鼠须管运行时 `rime_dict_manager` 导出/合并 | | |
| 6 | 雾凇全拼、小鹤双拼在鼠须管 1.1.2 上部署和打字 | | |

## 宿主机

- TRProbe（本机临时签名、未授权的独立 app，用 `open` 启动）：`path_exists=true`、`readable=true`、`open_rc=0`、`count=11`，**没有弹出权限对话框**，能直接读。
- `rime-type-probe` 在参考配置（`../squirrel-wubi86/rime` 副本）上：`g` → 一、`weixin` → 微信、`qukuailian` → 区块链、`neijuan` → 内卷，全部正确。日志显示 librime 加载了 `lua` 模块（插件在工具里也能加载）。

## 过程

### 验证 2：用授权弹窗安装（任务 4）

- 安装包签名：`Developer ID Installer: Yuncao Liu (28HU5A7B46)`，`Notarization: trusted by the Apple notary service`；`spctl`：`accepted`，`source=Notarized Developer ID`。
- 命令（通过 SSH 在桌面会话里运行，模拟应用里的 `NSAppleScript`）：
  `sudo launchctl asuser $(id -u) sudo -u tester osascript -e 'do shell script "installer -pkg /tmp/Squirrel-1.1.2.pkg -target /" with administrator privileges'`
- 测试机窗口弹出授权框，用户输入 tester 的密码后：`The install was successful.`、`The install requires logging out now.`，`exit=0`。
- 安装后 TIS：本体 `Squirrel` enabled=false；`Squirrel.Hans` enabled=true；`Hant` enabled=false。和 `install-test-log.md` 里用 `sudo installer` 的结果一致。
- `install.log` 里 postinstall 的输出：`User already registered Squirrel method(s): ["…Squirrel.Hans"]`、`User already enabled …`、`Selection fails for input source: …Squirrel.Hans`。说明 postinstall 拿到了桌面用户并以他的身份执行了注册和启用（选中失败是已知的系统限制，要用户在系统设置里添加）。
- 另有一行 `User notification authorization error: Couldn’t communicate with a helper application.`，不影响安装。
