# 阶段 3 测试机实测记录

日期：2026-10-15。环境：`squirrel-dev`（macOS 27.0.1，鼠须管 1.1.2，已添加并选中输入法）。`rimectl` 从共享文件夹运行，都在桌面会话里：`sudo launchctl asuser $(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' … --data-dir /tmp/rk`。

开始时 `~/Library/Rime` 里是阶段 0 手动放进去的雾凇完整方案，加上手写的 `default.custom.yaml`、`squirrel.custom.yaml`（都不是应用写的）。

| 场景 | 做法 | 结果 | 符合预期 |
|---|---|---|---|
| A 接手手动配置 | `settings init rime-ice` → `apply` → `apply --overwrite` → `status` | 第一次列出 `cn_dicts/…`、`default.custom.yaml`、`default.yaml` 等「不是应用写的，这次会被覆盖」，`exit=1`，什么都没写；第二次「已备份：…（第一次应用前）」「写入 69 个文件」「已通知鼠须管重新部署」「部署完成」，`exit=0`；`status` 外部改动：没有。打字检查（副本）：`nihao` → 你好，`rq` → 今天的日期 | ✅ |
| B 只改外观 | `settings set font-point 28` → `apply` | 先列出 `squirrel.custom.yaml：不是应用写的`（这是前面测部署信号时手写的；之前的设置不生成这个文件，所以把它当成不认识的文件保留着）→ `--overwrite` 后「写入 1 个文件，没变 69 个」「部署完成」。方案没重编译也判断出了部署完成。`build/squirrel.yaml` 里 `style` 和 `purity_of_form_custom` 的 `font_point` 都是 28。再改成 30、每页 7 个后，**用户在「文本编辑」里确认候选字明显变大、每页 7 个** | ✅ |
| C 外部改动 | 往 `default.custom.yaml` 末尾加一行 → `apply` → `apply --overwrite` | 第一次「default.custom.yaml：在应用外被改过」，`exit=1`；第二次写入 1 个文件，部署完成 | ✅ |
| D 编译失败 | 手写一个坏的 `rime_ice.custom.yaml`（应用不管的文件）→ 改字号 → `apply` | 「新配置编译不过，没有写入：rime_ice.custom.yaml 的格式不对（不是合法的 YAML）」，`exit=1`；`squirrel.custom.yaml` 的修改时间没变 | ✅ |
| E 鼠须管没运行 | `killall Squirrel` → 改每页候选数 → `apply` | 「已启动鼠须管」「部署完成」，`exit=0`；鼠须管在运行 | ✅ |
| F 还原 | `restore --list` → `restore <第一次应用前那份>` → `status` → `apply --overwrite` | 「已还原到 …（第一次应用前）」「还原前的状态也备份了」「部署完成」；手写的 `default.custom.yaml`、`squirrel.custom.yaml` 都回来了；`status` 应用管理的文件 0 个；再 `apply --overwrite` 回到应用管理的状态 | ✅ |

## 小发现

- 还原到「第一次应用前」再重新应用时，ledger 是空的、目录里又有配置，所以又会做一份「第一次应用前（永久保留）」的备份。来回多次会攒下多份永久备份。影响不大，记下来以后处理（例如：已经有永久备份时，新的就不再标永久）。
