# 阶段 6 实测记录：一键导出、在新电脑上导入

- 日期：2026-10-15
- 测试机：`squirrel-dev`（导出；Rime 目录由 `/tmp/rk` 管理，雾凇全拼，字号 24、每页 7 个）；新克隆的 `squirrel-import`（导入，测完删掉）
- 计划：[2026-10-15-phase6-transfer.md](superpowers/plans/2026-10-15-phase6-transfer.md) 任务 8

## 1. 在 `squirrel-dev` 里留下输入习惯

用户打 `shijian`，选第三个候选，重复 3 次：选的是「事件」「⌚️」「事件」（第一次选完后候选顺序变了）。

## 2. 导出

- 先试着直接写到共享文件夹 `/Volumes/My Shared Files/project/.build/`：失败，`Operation not permitted`。原因是共享文件夹本来就以只读方式挂载（`tools/vm/vm.sh` 里是 `:ro`）。鼠须管照样被重新启动了。
- 改成导出到测试机的 `/tmp/phase6-export.zip`，再用 `vm.sh ssh … 'cat …'` 拷到宿主机 `.build/`：
  - 输出：「导出输入习惯时会暂时退出鼠须管，几秒后自动启动」「已导出」「方案 1 个，个人词库 0 个，手动短语 0 条，输入习惯 1 份（文本替换生成的短语不导出）」
  - zip 里只有 `manifest.json`、`personal/`（空）、`personal/dicts/`（空）、`userdb/rime_ice.userdb.txt`
  - 导出后鼠须管进程又在运行（进程号变了）

## 3. 新克隆 `squirrel-import`：安装、添加输入法

- `./tools/vm/vm.sh new squirrel-import`，用户登录桌面。
- `rimectl install` →「已安装鼠须管 1.1.2」。
- `rimectl activate` 打开系统设置键盘页；用户添加鼠须管后自动继续：「已启动鼠须管」「鼠须管可以用了」。

## 4. 导入

`rimectl import '/Volumes/My Shared Files/project/.build/phase6-export.zip' --data-dir /tmp/rk`：

- 导出时间、「方案 1 个，个人词库 0 个，手动短语 0 条，输入习惯 1 份」
- 「已备份：…（导入前）」：新电脑的 Rime 目录里只有 Rime 自己的运行文件，没有配置文件，所以这份不用永久保留（符合设计）
- 「写入 70 个文件」「部署完成」「已合并输入习惯：rime_ice」，退出码 0
- 合并后鼠须管在运行；`~/Library/Rime` 里有 1 个 `*.userdb`

用户检查，全部正常：
- `nihao` → 你好
- 候选字 24 号、每页 7 个，和 `squirrel-dev` 一样
- `shijian`：「事件」排到了前面（输入习惯过来了）

## 5. 再导入一次

- 「应用里原来的设置和个人内容另存在：/tmp/rk/before-import/….zip」
- 「已备份：…（导入前，这份永久保留）」
- 「写入 0 个文件，没变 70 个」「部署完成」「已合并输入习惯：rime_ice」

确认：配置不会重复写，输入习惯可以重复合并。每导入一次会多一份永久备份和一个 `before-import` 文件（终审时已经提到，留到以后改进）。

最后删掉 `squirrel-import`，删掉两边的临时导出文件。

## 结论

- 导出、新电脑导入（含安装、添加输入法）全部跑通，打字效果和输入习惯都过来了。
- 测试机写不了共享文件夹（只读挂载）；以后在测试机里导出，都先导出到测试机自己的目录再拷出来。
