# 发布新版本

1. 改 `tools/app/Info.plist` 的 `CFBundleShortVersionString`（版本号）和 `CFBundleVersion`（每次加 1）。
2. 第一次在这台 Mac 上发布时，存公证凭据（App 专用密码由自己输入）：
   `xcrun notarytool store-credentials squirrel-helper-notary --apple-id <Apple ID> --team-id VS555M5VA8`
3. `swift test` 全部通过。
4. `./tools/release/build-release.sh`：release 编译 → Developer ID 签名（hardened runtime）→ 公证应用、钉票据 → 做 dmg（应用 + 指向「应用程序」的快捷方式）→ 给 dmg 签名 → 公证 dmg、钉票据 → 用 `tools/release/check-dmg.sh` 检查 → `.build/release-out/SquirrelHelper-<版本>.dmg` 和 `.sha256`。要公证两次（应用、dmg），一共要几分钟到十几分钟。只想试签名：`SKIP_NOTARIZE=1 ./tools/release/build-release.sh`。工作区要干净（有没提交的改动会被拒绝；试流程加 `ALLOW_DIRTY=1`）。签名时钥匙串可能问能不能用私钥，点「始终允许」。
5. 在干净的测试机里，从带隔离标记的 dmg 开始走一遍：打开 dmg、把应用拖进「应用程序」、再打开（做法见 [release-vm-log.md](release-vm-log.md)）。中文名、英文名都看一下（改系统语言后要注销再登录）。
6. 写 `docs/release-notes/<版本>.md`，然后：
   - `git tag v<版本> && git push origin v<版本>`
   - `gh release create v<版本> .build/release-out/SquirrelHelper-<版本>.dmg .build/release-out/SquirrelHelper-<版本>.dmg.sha256 --title "鼠须管助手 <版本>" --notes-file docs/release-notes/<版本>.md`（发正式版，不加 `--prerelease`；0.1.0、0.1.1 当时标成了预发布，0.2.0 起都是正式版）

- 签名身份默认是 `Developer ID Application: TONDA K.K. (VS555M5VA8)`，换身份用环境变量 `SIGN_IDENTITY`。
- 应用名：`Info.plist` 里是英文名 SquirrelHelper，`tools/app/*.lproj/InfoPlist.strings` 里给中文系统换成「鼠须管助手」。`.app` 的文件名必须是 `SquirrelHelper.app`，访达才会按语言换名字。检查各语言下显示什么（不运行应用）：`swift tools/app/display-name.swift .build/app/SquirrelHelper.app zh-Hans`。

## 发布方案清单

方案清单和应用是分开发布的：改清单不用发新版应用（在线方案清单设计 5.1）。

1. 改正本 `Sources/RimeKit/Resources/catalog.json`，`serial` 改大（日期加两位序号，例如 `2026102001`）。已经发布过的包 id、方案 id 不能删、不能改；要下架就标 `"deprecated": true`。要新代码才能用的包写 `"minAppVersion"`。
2. `swift test`；`RIMEKIT_ONLINE=1 swift test --filter OnlineTests`（会真的下载清单里的每个包）。加了新方案时，在 `OnlineGenerateTests` 里补一条打字检查，再跑 `RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests`；并在测试机里走一遍（见 `docs/superpowers/plans/2026-10-15-online-catalog.md` 任务 12）。
3. `./tools/catalog/publish.sh`：校验（serial 变大、id 没删）→ 复制到 `catalog/v1/` → 用钥匙串里的私钥签名。钥匙串问能不能用时点「始终允许」。
4. 问过以后提交、推送 `main`。
5. `./tools/catalog/publish.sh --verify-remote`：从 GitHub 拉回来再验一次（GitHub 的 raw 文件有几分钟缓存）。

发应用新版前，先确认正本已经发布（`catalog/v1/catalog.json` 和正本一样）。不然内置清单比在线的新，在线那份就不起作用了——不会出错，但说明漏了一步。

密钥：第一次用 `./tools/catalog/keygen.sh` 生成，私钥在登录钥匙串（服务名 `squirrel-macos-catalog-signing`），**要另外备份**。私钥丢了只能发新版应用换公钥。

开发用的隐藏命令（不在 `rimectl --help` 里）：`rimectl catalog keygen`、`catalog sign <文件> --out <签名文件>`（私钥从标准输入读）、`catalog verify <文件> <签名文件>`、`catalog verify-source <新清单> [<上次发布的清单>]`。debug 编译的 RimeKit 认两个环境变量，测试机实测用：`RIMEKIT_CATALOG_URL`（换清单地址）、`RIMEKIT_CATALOG_TEST_PUBKEY`（多认一个测试公钥）。release 编译里没有。
