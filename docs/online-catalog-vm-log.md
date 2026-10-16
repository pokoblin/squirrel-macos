# 在线方案清单：测试机实测记录

- 日期：2026-10-16
- 测试机：长期的 `squirrel-dev`（macOS 27.0.1，已装鼠须管 1.1.2，`~/Library/Rime` 里是雾凇全拼和小鹤双拼）
- 计划：[2026-10-15-online-catalog.md](superpowers/plans/2026-10-15-online-catalog.md) 任务 12
- 正式在线清单已在任务 11 发布（编号 2026101501），`publish.sh --verify-remote` 推送后立即通过

## 第一部分：rimectl + 测试清单（测试密钥）

宿主机用 `rimectl catalog keygen` 生成一对测试密钥，从正本做一份测试清单：编号 `2099010101`；雾凇的 `include` 多一项 `README.md`（算规则变化，不影响生成）；极点五笔 86 标下架。签名后用 `python3 -m http.server` 只把清单目录发给测试机（`http://192.168.64.1:8765/`），测试私钥不在这个目录里。

测试机里用一个小脚本 `/tmp/rc.sh` 设好 `RIMEKIT_CATALOG_URL`、`RIMEKIT_CATALOG_TEST_PUBKEY` 再运行 debug 版 rimectl。

| 步骤 | 结果 | |
|---|---|---|
| 新数据目录 `catalog show` | 用的是内置方案清单（编号 2026101501） | ✅ |
| `catalog check` | 方案清单更新了（编号 2099010101）；你在用的这些方案包的安装规则变了：雾凇拼音；这些方案包下架了：极点五笔 86；提示运行 apply | ✅ |
| 再 `catalog show` | 用的是在线方案清单（编号 2099010101，某日下载） | ✅ |
| 再 `catalog check` | 方案清单已经是最新的 | ✅ |
| 清单改了编号、不重新签名 | 没有用上新的方案清单：方案清单的签名不对，没有采用；退出码 1；仍用 2099010101 | ✅ |
| 重新签一份删掉 `double_pinyin_flypy` 的清单 | 没有用上：这份方案清单和你现在的设置对不上（方案清单里没有这个方案：double_pinyin_flypy），请更新应用；仍用 2099010101 | ✅ |
| 桌面会话里 `takeover --confirm` → `catalog check` → `apply` | 接管 70 个文件，永久备份；检查到规则变化；应用：没变 70 个，部署完成 | ✅ |
| 在 Rime 目录副本上打字 | `nihao`→你好，`weixin`→微信，小鹤 `nihc`→你好 | ✅ |

## 第二部分：应用（正式清单）

`./tools/vm/install-app.sh squirrel-dev` 装上应用（应用默认的数据目录是空的，先走引导、接管已有配置）。由用户在界面上检查：

| 步骤 | 结果 | |
|---|---|---|
| 「方案」页 | 有「检查方案清单更新」按钮和联网说明的灰字；点了提示「方案清单已经是最新的」 | ✅ |
| 「诊断」页 | 「应用什么时候会联网」三行表格、「以上都只下载……」，「现在用的是应用内置的方案清单（编号 2026101501）」 | ✅ |
| 退出应用，放一份从 GitHub 下载、末尾多一个空格的缓存清单，再打开 | 应用照常打开；诊断页橙色字「在线方案清单的缓存用不了：缓存的方案清单签名不对。先用内置的」 | ✅ |

测完删掉了测试机里的缓存清单、`/tmp/rk-check`，停掉了宿主机的 http 服务，删掉了测试密钥。`/tmp/rk-catalog`（rimectl 接管时用的数据目录）留着，下次重启测试机会被清掉。

## 顺带发现、已经修了的

| 问题 | 处理 |
|---|---|
| `keygen.sh` 存好私钥后报 `SERVICE�: unbound variable` 退出，公钥没打印出来 | macOS 自带的 bash 3.2 在 UTF-8 环境下会把 `$SERVICE）` 里全角括号的字节当成变量名。改成 `${SERVICE}`；`build-release.sh`、`test-rime-type-probe.sh` 里同样的写法一起改（d994469）。那把私钥删掉重新生成 |
| 用户从终端复制公钥时剪贴板里不是公钥 | 改成从钥匙串里的私钥算出公钥写进文件，私钥只经过管道 |
| `tart run` 共享整个项目目录时报「directory sharing device configuration is invalid」 | `--dir=project:…/squirrel-macos:ro` 会被 tart 2.41 解析错，路径末尾加 `/` 就好。`vm.sh new` 一起改 |
| 测试机的 zsh 不拆变量里的空格：`$R … $D`（`D='--data-dir /tmp/x'`）让 `--data-dir` 没生效，写进了默认数据目录 | 发现后删掉了误写的目录；改用一个 bash 小脚本包住 rimectl |
