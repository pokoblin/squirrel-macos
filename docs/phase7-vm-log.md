# 阶段 7 实测记录：文本替换同步

- 日期：2026-10-15
- 测试机：`squirrel-dev`（Rime 目录由 `/tmp/rk` 管理，雾凇全拼；开始时同步关着）
- 计划：[2026-10-15-phase7-text-replacement.md](superpowers/plans/2026-10-15-phase7-text-replacement.md) 任务 6

## 0. 途中发现：宿主机重新编译后，测试机里直接运行共享文件夹里的 rimectl 会被系统杀掉

- 现象：`'/Volumes/My Shared Files/project/.build/debug/rimectl' …` 没有任何输出，退出码 137（SIGKILL），连 `catalog` 都一样。
- 宿主机刚用 `swift build` 原地重新编译过这个文件。今天早些时候（阶段 6）同样的路径还能运行。
- 把 `rimectl` 和旁边的资源包 `SquirrelMacOS_RimeKit.bundle` 一起复制到测试机的 `/tmp/rimectl-bin/` 再运行，就正常了（只复制 `rimectl` 会报找不到资源包）。
- 推测：测试机缓存了旧文件的代码签名信息，文件被原地改写后对不上，系统直接杀掉进程。没有深究。
- 以后在测试机里跑 rimectl：先复制到测试机本地再运行（已写进 `CLAUDE.md`）。

## 1. 看状态、打开同步

| 命令 | 结果 |
|---|---|
| `textreplacement status` | 「macOS 文本替换：2 条能用」（系统自带 1 条 + 阶段 0 加的 `tstx`），「同步：没打开」 |
| `textreplacement sync --cache-only` | 「写入 1 个文件，没变 69 个」「部署完成」 |
| `textreplacement status` | 「同步：已打开，和上次同步时一样」 |
| `doctor --offline` | 「[正常] 文本替换：2 条，和上次同步时一样」 |

## 2. 用户加两条文本替换

用户在系统设置里加了 `tsxj` →「测试新加」、`ts2` →「打不出来」。

| 命令 | 结果 |
|---|---|
| `textreplacement status` | 「3 条能用；1 条快捷码里有数字或符号，Rime 里打不出来，跳过」「和上次同步比：新增 1 条，删掉 0 条」 |
| `doctor --offline` | 「[注意] 文本替换：有变化没同步：新增 1 条，删掉 0 条 → 运行 rimectl textreplacement sync」 |
| `textreplacement sync --cache-only` | 「写入 1 个文件」「部署完成」 |

用户打字检查（雾凇全拼）：`tstx` → 测试短语，`tsxj` → 测试新加，都正常。

## 3. 关掉同步、还原

| 命令 | 结果 |
|---|---|
| `textreplacement off --cache-only` | 「写入 1 个文件」「部署完成」 |
| `status` | 外部改动：没有 |
| `textreplacement status` | 「同步：没打开」 |

用户确认 `tsxj` 不再出「测试新加」，然后在系统设置里删掉了 `tsxj`、`ts2`（`tstx` 留着）。`/tmp/rk` 回到同步关着的状态。

## 结论

- 加文本替换后 `status`、`doctor` 都看得出变化；跳过的条目按原因数出来了；同步后打得出新加的；关掉同步后文本替换的短语去掉了。
- 输出里只有条数，没有文本替换的内容。
