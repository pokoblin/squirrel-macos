# 阶段 5 实测记录：接管已有配置

- 日期：2026-10-15
- 测试机：`squirrel-dev`（鼠须管 1.1.2；Rime 目录由 `/tmp/rk` 管理，雾凇全拼）
- 计划：[2026-10-15-phase5-takeover.md](superpowers/plans/2026-10-15-phase5-takeover.md) 任务 10

## 1. 接管应用自己生成的雾凇配置

把 `/tmp/rk/packages` 复制到新的数据目录 `/tmp/rk5`，用 `--cache-only`（和 `/tmp/rk` 用同一个上游版本）。

| 步骤 | 结果 | |
|---|---|---|
| `takeover --cache-only --data-dir /tmp/rk5` | 方案 `rime_ice`；外观「候选字字号 24，每页 7 个候选」，和 `/tmp/rk/settings.json` 一致；「换掉 0 个文件，内容不变 70 个，新加 0 个，原样保留 2 个（`LICENSE`、`weasel.yaml`）」 | ✅ |
| `takeover --confirm …` | 「已备份：…（第一次应用前，这份永久保留）」「写入 70 个文件」（第一次没有记录可比，内容相同的也重写一遍）「部署完成」 | ✅ |
| 再 `apply` | 「写入 0 个文件，没变 70 个」 | ✅ |
| 删掉 `/tmp/rk5` 后 `status --data-dir /tmp/rk` | 外部改动：没有 | ✅ |

## 2. 真实上游的五笔脱敏样本

`RIMEKIT_ONLINE=1 RIMEKIT_SAMPLE_OUT=.build/wubi-sample swift test --filter OnlineTakeoverTests` 造样本（照 [reference-wubi-profile.md](reference-wubi-profile.md) 的改法；个人词库和短语是编的）。测试机的 Rime 目录先整份复制到 `/tmp/rime-before-phase5`，再换成样本（保留 `user.yaml`、`installation.yaml`、`*.userdb`）。

预览（`takeover --data-dir /tmp/rk6`）：

- 方案：五笔拼音混输排第一的 6 个方案
- 选项：拼音词库 = 雾凇大词库
- 外观：候选字字号 24，序号字号 20，注释字号 20
- 保留的补丁：`default.custom.yaml` 里的 `key_binder/bindings`（`-` `=` 翻页）
- 个人词库 2 个（`pinyin_user.dict.yaml`、`wubi86_jidian_user.dict.yaml`）；手动短语 1 条；和文本替换一样的 1 条（测试机里加过的 `tstx`）
- 换掉 9 个、不变 16 个、新加 1 个（`numbers.custom.yaml`：生成规则给每个启用的方案注入短语翻译器）、原样保留 2 个（`default.custom.yaml.bak`、`weasel.custom.yaml`）
- 没有「注意」

`--confirm`：「第一次应用前，这份永久保留」「写入 26 个文件」「部署完成」。

用户在测试机里打字检查（五笔拼音混输），全部正常：`g` → 一，`weixin` → 微信，`qukuailian` → 区块链，`tstx` → 测试短语（文本替换），`sdzd` → 手动短语样本，`shuxuguanyangbenci` 有「鼠须管样本词」（个人拼音词库），`tgtg` 有「五笔样本词」（个人五笔词库），候选字 24 号，`-` `=` 能翻页。

再 `apply`：「写入 0 个文件，没变 26 个」。

还原：删掉样本、复制回 `/tmp/rime-before-phase5`、`Squirrel --reload`；`status --data-dir /tmp/rk` 外部改动：没有。

## 3. 途中发现：测试机里鼠须管的输入源不见了

打字检查前，用户发现测试机里鼠须管用不了：在系统设置里添加后，输入法菜单里也找不到。

- `tis-probe` 列出的输入源里一个 `im.rime.inputmethod.*` 都没有（不是没启用，是系统里没注册）；鼠须管进程在运行，`/Library/Input Methods/Squirrel.app` 还在。`rimectl doctor` 报「系统里没有鼠须管的输入源」，建议 `install --force`。
- 安装日志：阶段 4 收尾时（15:40）用 `install --force` 覆盖重装过一次，当时 postinstall 写的是「User already registered … Squirrel.Hans」「Default method not enabled yet」，说明那时还是注册着的。丢失发生在 15:40 到 16:29 之间，原因没查清。
- 在桌面会话里运行 `Squirrel --register-input-source`，三个输入源马上回来了（本体 enabled=true，是用户刚加的）。
- 再 `install --force` 覆盖重装一次，注册没有丢，postinstall 还自动选中了鼠须管。**没能复现。**
- 重装后鼠须管进程被安装脚本关掉，要 `open` 一下才启动。

结论：根因不明，先记下。值得以后改进的地方：输入源没注册时，`doctor` 建议的 `install --force` 不一定有用（postinstall 如果认为「已经注册过」就跳过注册）；`activate` 可以先跑一次 `Squirrel --register-input-source` 再等用户添加。

**后续（已改）**：`rimectl activate` 发现系统里没有鼠须管的输入源时，先运行 `Squirrel --register-input-source`，让 run loop 转一下再查（最多 5 秒）。回来了就停下，提示「请再运行一次 rimectl activate」（原因见下面的实测）；还是没有才报错，建议注销再登录或 `install --force`。`doctor` 的建议改成 `rimectl activate`。

后来在 squirrel-dev 里复现出来了（同一天 17:00 前后）：
- 退出鼠须管，把 `Squirrel.app` 移出 `/Library/Input Methods`，只等 30 秒：三个输入源都还在。
- 再删掉 `$(getconf DARWIN_USER_CACHE_DIR)/com.apple.IntlDataCache.le*`、杀掉 `TextInputMenuAgent`/`TextInputSwitcher`：第一次试时还列着（名字变成 `?`）；注销再登录（app 不在）后一个都没有了。之后在新登录的会话里，同样的三步做完，3 秒内就一个都没有了。缓存文件会被任何用到 TIS 的进程重建（日志 `TISFileInterrogator updateSystemInputSources`）。
- 把 `Squirrel.app` 移回去：**新进程**马上就能看到三个输入源，本体 enabled=true，不用重新注册（这时 `--register-input-source` 打印「User already registered」）。原来那次是 app 一直在、输入源却一直没有，要手动注册才回来，和这里不完全一样，根因还是不清楚。
- 用 `lsregister -u` 把鼠须管从 LaunchServices 里注销，再注销、登录：输入源照样都在。TIS 不靠 LaunchServices，直接扫目录。之后用 `lsregister -f -R` 注册回去了。
- **同一个进程的状态是旧的**：在输入源消失时就已经启动的进程，app 移回去后能看到输入源回来，但本体的 enabled 一直是 false，新进程看到的是 true。用 `CFRunLoopRunInMode` 转 run loop、在本进程里调 `TISRegisterInputSource`、自己发 `kTISNotifyEnabledKeyboardInputSourcesChanged` 分布式通知，都刷新不了。第一版的 `activate` 就是因此在重新注册后打开了系统设置，白等了 30 秒。
- 改成重新注册后就停下以后：第一次 `rimectl activate` 输出「系统里没有鼠须管的输入源，正在重新注册……」「已重新注册鼠须管的输入源，请再运行一次 rimectl activate」（退出码 1）；第二次「已启动鼠须管」「鼠须管可以用了」；`doctor` 全部正常。`doctor` 在没有输入源时报「系统里没有鼠须管的输入源 → 运行 rimectl activate（会重新注册输入源）」。

## 4. 宿主机真实配置（只读，经用户同意）

复制 `~/Library/Rime` 到临时目录（删掉 `build/`），只跑预览，跑完删掉副本。只记录设置、文件名和条数。

- 方案：五笔拼音混输排第一的 6 个方案；拼音词库 = 雾凇大词库
- 外观：候选字字号 24，序号字号 20，注释字号 20
- 保留的补丁：`default.custom.yaml` 里的 `key_binder/bindings`；`squirrel.custom.yaml` 里两个配色的 `candidate_font_point`（无效键，原来的配置里也改过它；原样保留不影响什么）
- 个人词库 1 个（`pinyin_user.dict.yaml`；`wubi86_jidian_user.dict.yaml` 和上游一样，不算）
- 手动短语 0 条；和文本替换一样的 11 条（全部对得上）
- 换掉 9 个、不变 16 个、新加 1 个（`numbers.custom.yaml`）、原样保留 3 个（`default.custom.yaml.bak`、`squirrel.custom.yaml.bak`、`weasel.custom.yaml`）
- 没有「注意」

和 [reference-wubi-profile.md](reference-wubi-profile.md) 的描述一致。
