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
