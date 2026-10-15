# 阶段 4 测试机实测记录

## 实测 1：同一个进程里能不能看到用户在系统设置里的添加

日期：2026-10-15。环境：`squirrel-dev`（已装鼠须管 1.1.2）。

做法：在桌面会话里同时跑两个 `tis-probe watch`，各 300 秒，每秒查一次主输入源 `im.rime.inputmethod.Squirrel` 的 enabled。一个每次等待用 `CFRunLoopRunInMode`（`pump`），一个用 `Thread.sleep`（`sleep`）。用户在「系统设置 → 键盘 → 文字输入 → 编辑…」里删掉鼠须管，等 10 秒再加回来。

| 等法 | 输出 |
|---|---|
| `pump`（让 run loop 转） | `0s enabled=true` → `57s enabled=false` → `74s enabled=true`：删除和加回都看到了 |
| `sleep`（干等） | 只有 `0s enabled=true`，**删除和加回都没看到** |
| 对照：新开一个进程查 | 本体 enabled=true（加回来了），但「鼠须管 - 简体」没有被选中 |

**结论**：TIS 的状态在进程里有缓存，靠系统通知更新，等待时必须让 run loop 转起来才看得到用户的添加。任务 5 的 `pump` 按计划用 `CFRunLoopRunInMode`。另外，用户重新添加后鼠须管不会自动被选中，`activate` 要主动切换过去。

## 实测 2：干净测试机上的新电脑流程

日期：2026-10-15。环境：从 `macos-base` 新克隆的 `squirrel-fresh`（macOS 27.0.1，什么都没装），用户登录桌面。`rimectl` 从共享文件夹在桌面会话里运行，数据目录 `/tmp/rk`。

| 步骤 | 命令 | 结果 | 符合预期 |
|---|---|---|---|
| 环境检查 | `doctor` | `[问题] 鼠须管：还没有安装 → 运行 rimectl install`，`exit=1` | ✅ |
| 授权框安装 | `install --gui-auth` | 弹出系统授权框，用户输密码 →「已安装鼠须管 1.1.2」，`exit=0` | ✅ |
| 授权框取消 | `install --gui-auth --force` | 用户点「取消」→「你取消了授权，鼠须管没有安装」，`exit=1`；`Squirrel.app` 修改时间没变，暂存区是空的 | ✅ |
| 免密 sudo | `install` → `install --force` | 「已经装了鼠须管 1.1.2，是最新的，不用装」；`--force` 时不弹框，「已安装鼠须管 1.1.2（原来是 1.1.2）」 | ✅ |
| 装好后检查 | `doctor` | 已安装 1.1.2（是最新版）；`[问题] 输入法：还没有在系统设置里添加鼠须管` | ✅ |
| 启用（第一次） | `activate` | 打开了系统设置；用户添加后 **rimectl 崩溃**（SIGTRAP，崩在 Carbon 的 `islGetInputSourceProperty`，主线程正在处理 TIS 的通知）。原因：在后台线程查 TIS 状态，和主线程处理「输入源变了」的通知撞车。另外发现通过 SSH 时输出要等命令结束才显示 | ❌ → 已修 |
| 修复 | — | TIS 的调用都放到主线程（`TISInputSourceService.onMain`）；`rimectl` 每行输出后 `fflush` | — |
| 启用（修复后重测） | 用户先删掉鼠须管 → `activate` → 用户加回来 | 立即显示「已打开系统设置的键盘页……」；用户加回后「已启动鼠须管」「鼠须管可以用了」，`exit=0`；没有新的崩溃报告 | ✅ |
| 启用后检查 | `doctor` | 鼠须管、输入法（已添加并选中）、进程、Rime 目录都是 `[正常]`，`exit=0` | ✅ |
| 应用起步设置 | `settings init wubi-pinyin` → `apply` | 「已备份：…（第一次应用前）」「写入 23 个文件」「部署完成」，`exit=0`（新电脑上 Rime 目录里只有鼠须管的运行文件，没有要确认的） | ✅ |
| 打字 | 打字检查（副本）+ 用户在「文本编辑」里打字 | `g` → 一、`weixin` → 微信、`qukuailian` → 区块链；用户打 `weixin` 第一个候选是「微信」 | ✅ |

测完删掉了 `squirrel-fresh`。
