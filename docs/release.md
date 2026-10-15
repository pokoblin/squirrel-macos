# 发布新版本

1. 改 `tools/app/Info.plist` 的 `CFBundleShortVersionString`（版本号）和 `CFBundleVersion`（每次加 1）。
2. 第一次在这台 Mac 上发布时，存公证凭据（App 专用密码由自己输入）：
   `xcrun notarytool store-credentials squirrel-helper-notary --apple-id <Apple ID> --team-id VS555M5VA8`
3. `swift test` 全部通过。
4. `./tools/release/build-release.sh`：release 编译 → Developer ID 签名（hardened runtime）→ 公证 → 钉票据 → `.build/release-out/SquirrelHelper-<版本>.zip` 和 `.sha256`。公证一般要几分钟。只想试签名：`SKIP_NOTARIZE=1 ./tools/release/build-release.sh`。签名时钥匙串可能问能不能用私钥，点「始终允许」。
5. 在干净的测试机里，从带隔离标记的 zip 开始走一遍（做法见 [release-vm-log.md](release-vm-log.md)）。中文名、英文名都看一下（改系统语言后要注销再登录）。
6. 写 `docs/release-notes/<版本>.md`，然后：
   - `git tag v<版本> && git push origin v<版本>`
   - `gh release create v<版本> .build/release-out/SquirrelHelper-<版本>.zip .build/release-out/SquirrelHelper-<版本>.zip.sha256 --title "鼠须管助手 <版本>" --notes-file docs/release-notes/<版本>.md`（0.x 版本加 `--prerelease`）

- 签名身份默认是 `Developer ID Application: TONDA K.K. (VS555M5VA8)`，换身份用环境变量 `SIGN_IDENTITY`。
- 应用名：`Info.plist` 里是英文名 SquirrelHelper，`tools/app/*.lproj/InfoPlist.strings` 里给中文系统换成「鼠须管助手」。`.app` 的文件名必须是 `SquirrelHelper.app`，访达才会按语言换名字。检查各语言下显示什么（不运行应用）：`swift tools/app/display-name.swift .build/app/SquirrelHelper.app zh-Hans`。
