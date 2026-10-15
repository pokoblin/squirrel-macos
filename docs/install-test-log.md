# 从零安装实测记录

日期：2026-10-15。环境：Tart 虚拟机，macOS 27.0.1（和宿主机同一个版本），从干净底板克隆。鼠须管 1.1.2 官方安装包。

## 要回答的问题

1. 不用 Homebrew，能不能直接装鼠须管？
2. 装完到底要不要注销才能用？
3. 新电脑上，“恢复一整套配置”的流程会卡在哪里？

## 结论

| 问题 | 结论 |
|---|---|
| 不用 Homebrew 能装吗 | **能**。Homebrew 本来就只是下载官方 pkg 再运行它 |
| 装完要注销吗 | **不用**。安装程序会提示“需要注销”，但实测不注销也能用；**反过来，光注销也没用** |
| 补充（2026-10-15，修复 0.1.1 时的干净测试机） | **有时要注销**：在应用里装好鼠须管后，安装包脚本按旧的输入源数据误报「已经启用」，系统设置里有鼠须管、输入法菜单里没有、打出来是英文；注销再登录后正常。应用的完成页因此加了「注销再登录一次」的提醒。见 [backlog-fixes-vm-log.md](backlog-fixes-vm-log.md) |
| 那必须做什么 | **用户必须在「系统设置 → 键盘 → 输入法」里手动添加一次鼠须管**。程序没法替代这一步，系统也没有任何弹窗 |
| 恢复配置卡在哪里 | 复制配置、部署都正常。只有导入文本替换时调用 python3，新 Mac 上会弹窗要求安装开发者工具 |
| 打字 | 恢复配置后：`g` → 一（五笔），`weixin` → 微信（拼音混输），`qukuailian` → 区块链（雾凇新词），候选字是自定义的 24 号字 ✅ |

## 对前端设计的影响

- 下载、校验、安装鼠须管，放配置，部署：**都可以由应用自动完成**。安装时用户要输一次管理员密码（系统授权框）。
- **在系统设置里添加输入法：必须引导用户亲手做。** 应用可以一键打开系统设置的键盘页，配上图文说明，并**自动检测**是否添加好了（看本体 `im.rime.inputmethod.Squirrel` 是否 enabled）。检测到后，应用可以直接帮用户切换过去。
- **不要让用户注销。** 安装程序的“需要注销”提示可以忽略（用 `installer` 命令安装时，它只是打印一行提示）。
- 不能依赖 python3、git。

---

## 过程

用到的工具：
- `tools/vm/vm.sh`：克隆测试机。
- `tools/vm/tis-probe.swift`：查看和切换输入源，用的是 Carbon 的 TIS（Text Input Sources）接口。
- 测试机里，输入法相关的命令都用“当前登录用户的桌面会话”运行：`sudo launchctl asuser $(id -u) sudo -u tester …`。

### 测试机 1：先试各种程序方法，再注销，最后在系统设置里添加

| 步骤 | 结果 |
|---|---|
| 安装前 | 只有 ABC 键盘和日文输入法 |
| `sudo installer -pkg Squirrel-1.1.2.pkg -target /` | 8 秒装完，提示 `The install requires logging out now.` |
| 安装后查状态 | `Squirrel.Hans` enabled=true；**本体 `Squirrel` enabled=false**；`Hant` enabled=false；当前仍是 ABC；鼠须管进程没运行；`~/Library/Rime` 还不存在 |
| `TISSelectInputSource(Squirrel.Hans)` | **OSStatus -50**（参数错误） |
| `Squirrel --enable-input-source` | 输出 `User already enabled Squirrel method(s): ["…Squirrel.Hans"]` |
| `Squirrel --select-input-source` | 输出 `Selection fails for input source: …Squirrel.Hans` |
| `TISEnableInputSource(本体)` | 返回 0，但本体仍是 enabled=false |
| **对照**：同样方法切换到日文、再切回 ABC | 都成功 → 说明测试方法没问题，是鼠须管本身切不了 |
| 用户看输入法菜单 | **看不到鼠须管** |
| `open` 启动鼠须管程序 | 进程起来了，自动生成 `~/Library/Rime`，但仍然切换不了 |
| `killall TextInputMenuAgent`（会自动重启），再重新注册、启用 | 还是切换不了 |
| **注销，再登录** | 状态**完全一样**：本体 enabled=false，菜单里看不到，切换返回 -50 |
| 用户在系统设置里手动添加鼠须管（列表里能找到，没有弹窗） | 本体变成 enabled=true，**切换成功（OSStatus 0）**，鼠须管进程启动了（当时用户紧接着就在打字。2026-10-15 在 squirrel-dev 上发现：只切换、不打字时，进程不会自己启动，见 [phase0-log.md](phase0-log.md)） |
| 从共享文件夹运行 `restore.sh` 恢复配置 | 配置复制成功，部署成功；但调用 python3 时打印 `xcode-select: note: No developer tools were found, requesting install.`，桌面弹出安装开发者工具的窗口（用户点了取消） |
| 实际打字 | 全部正常 |

### 测试机 2：全程不注销

| 步骤 | 结果 |
|---|---|
| 登录桌面后安装 | 和测试机 1 一样：本体 enabled=false，切换返回 -50 |
| **不注销**，用户直接在系统设置里添加 | 「简体中文」里能找到鼠须管；添加后本体 enabled=true，**切换成功** |
| 复制配置（`rsync`）后运行 `Squirrel --reload` | **没反应**：这时鼠须管进程还没运行，没有程序接收重新部署的通知 |
| `open` 启动鼠须管 | 启动时自动部署，`wubi86_jidian.table.bin`、`pinyin_ext.table.bin` 都生成了 |
| 实际打字 | 全部正常 |

## 还没测的

- 用图形界面双击 pkg 安装（不是 `installer` 命令），最后的“注销”按钮能不能跳过。
- 安装时不在桌面登录状态（比如只有 SSH 会话）会怎样：postinstall 用 `stat -f%Su /dev/console` 取当前桌面用户。
- 已经装过旧版鼠须管的电脑上升级。（`rimectl install` 在已装版本比最新旧时会升级，阶段 4 用假数据测过；真机升级没测。鼠须管自带 Sparkle，也会自己升级。）
- ~~打开系统设置键盘页的链接是否有效~~：已验证能用，见 [phase0-log.md](phase0-log.md)。
- ~~前端 .app 自己读取 `TextReplacements.db` 会不会被隐私权限拦住~~：已验证不会被拦（未签名、不开沙盒），见 [phase0-log.md](phase0-log.md)。
