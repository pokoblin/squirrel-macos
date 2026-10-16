# 试打预览：测试机实测记录

- 日期：2026-10-16
- 测试机：长期的 `squirrel-dev`（macOS 27.0.1，鼠须管 1.1.2 / librime 1.16.0，雾凇全拼）
- 计划：[2026-10-16-typing-preview.md](superpowers/plans/2026-10-16-typing-preview.md) 任务 10

## 第一部分：debug 包（临时签名）

`./tools/vm/install-app.sh squirrel-dev` 装上应用，由用户在界面上按清单逐项试：

| 步骤 | 结果 | |
|---|---|---|
| 进「试打」页 | 来源默认是「当前生效」 | ✅ |
| 输入 `nihao` | 出「你好 👋」 | ✅ |
| 数字选词、点击选词、空格上屏 | 正常 | ✅ |
| `-` `=` 和 PageUp / PageDown 翻页 | 正常 | ✅ |
| 上下键移动高亮 | 正常 | ✅ |
| 退格、Esc | 正常 | ✅ |
| 已上屏的字累加、快速连打 | 累加正常，不乱序 | ✅ |
| `rq` 出日期、`xiaolian` 出 emoji（Lua、OpenCC） | 正常 | ✅ |
| `wo`、`3`、`wo3`（librime 不处理的字符） | 原样上屏 | ✅ |
| 切到别的页面再回来 | 不空白 | ✅ |
| 应用改动后 | 试打页出现「配置变了 / 重新载入」 | ✅ |
| ⌘W、小键盘回车 | 照常 | ✅ |

## 第二部分：发布签名的包

`ALLOW_DIRTY=1 SKIP_NOTARIZE=1 ./tools/release/build-release.sh`（提交 c25eb3c，Developer ID `VS555M5VA8`，没有公证）。debug 包没有 hardened runtime，试不出库验证的问题，所以这一步必须测。

| 步骤 | 结果 | |
|---|---|---|
| 主程序签名 | `flags=0x10000(runtime)`，没有 `disable-library-validation` | ✅ |
| 辅助程序 `Contents/Helpers/rime-preview-helper` 签名 | 也是 runtime，带 `disable-library-validation` | ✅ |
| `check-entitlements.sh --release` | 输出 ok | ✅ |
| 直接运行包里的辅助程序，在 /tmp 的副本上 `open rime_ice`、`input nihao` | `librimeVersion` 1.16.0，候选「你好 \| 👋 \| 拟好 \| 你 \| 尼…」 | ✅ |
| 用户在应用界面里试打 | 正常 | ✅ |

结论：发布签名下，辅助程序带 entitlement 就能加载鼠须管的 librime，主程序不需要（verified-facts 8.1 的小试验在真实应用包里得到确认）。公证还没做，第一次正式发版时确认。

## 第三部分：真实目录没有被动

试之前和试之后，对测试机 `~/Library/Rime` 所有文件（102 个）做 `stat -f "%m %z %N"` 列表，`diff` 完全一致（鼠须管同时在运行）。

## 测试中发现、已经修了的

| 问题 | 处理 |
|---|---|
| 分段控件里单个选项的 `.disabled` 在 macOS 上不生效：没有未应用的改动时也能点「应用后的样子」，模型拒绝切换，控件却停在那一段，一打字就弹回「当前生效」 | 没有改动时整个「来源」禁用，并写「没有未应用的改动」（44c2811）。记进 verified-facts 8.1 |
| 用户以为「应用后的样子」能看出外观（字号）变化 | 按设计看不出：候选窗口由鼠须管绘制，不经过 librime。试打页顶部加了一行说明（c25eb3c）。想做外观预览见 `docs/backlog.md` 最后一节 |

## 已知的小问题（记在 backlog）

- 用 `pkill` 结束应用时 `onDisappear` 不运行，`staging/preview-*` 副本会留下，要等某次启动时超过 1 小时才被 `cleanStaleStaging` 删掉。「应用后的样子」副本约 70 MB（真实编译结果，不是克隆）。

## 传文件的坑

宿主机重建 `.build/app` 后，测试机的共享文件夹一时看不到新文件：应用用 `tar … | vm.sh ssh … 'tar -x'` 传，dmg 用 `cat >` 传（`CLAUDE.md` 里已有类似说明）。
