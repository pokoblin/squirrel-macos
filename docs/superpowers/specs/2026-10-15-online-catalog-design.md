# 在线方案清单设计

- 日期：2026-10-15
- 状态：**已和用户逐段确认（2026-10-15）**，等用户看完整份文档
- 属于：第二版的第 1 个子项目（见 [第二版路线图](../plans/2026-10-15-v2-roadmap.md)）
- 依据：[第一版设计](2026-10-15-squirrel-macos-v1-design.md) 第 4 节（清单格式按「以后能放到网上」设计）

---

## 1. 目标

应用能装哪些方案，写在打包进应用的 `catalog.json` 里。现在想加新方案，或者上游改了目录结构（检查发现缺文件、装不上），都得发新版应用。

在线清单要做到两件事（用户确认：两个都要）：

1. 不发版就能加新方案；
2. 上游改了结构时，改一下网上的清单就能修好。

清单只能描述已有的能力（下载哪个 zip、装哪些文件、选项生成哪些总词库和补丁）。需要新代码的包，用 `minAppVersion` 挡住旧应用（见 3.4）。

### 用户定下的几件事

| 问题 | 决定 |
|---|---|
| 防篡改 | **签名**（Ed25519）。清单决定从哪个仓库下载方案，方案里的 Lua 脚本会在鼠须管里运行，清单被改就等于能在用户电脑上跑代码 |
| 放在哪里 | **只用 GitHub**（本项目仓库，`raw.githubusercontent.com`），不配镜像 |
| 什么时候拉 | **只在用户点「检查方案清单更新」时拉**，应用不自己联网拉清单（例外见 4.5） |
| 联网说明 | 界面上要有合适的位置告诉用户：什么时候联网、连哪里、传了什么 |

---

## 2. 文件和地址

| 文件 | 作用 |
|---|---|
| `Sources/RimeKit/Resources/catalog.json` | **唯一的正本**。改清单只改这里；应用打包时带上，就是内置清单 |
| `catalog/v1/catalog.json` | 发布出去的副本，由发布脚本从正本复制 |
| `catalog/v1/catalog.json.sig` | 上面那个文件的签名（base64 文本） |

应用拉取的地址：

```
https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json
https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json.sig
```

路径里的 `v1` 是格式版本（`Catalog.supportedFormatVersion`）。以后格式改得不兼容，就发到 `v2/`，旧应用继续拉 `v1/`，不会拉到看不懂的格式。`v1/` 在旧应用还有人用时继续维护。

应用数据目录里新增：

```
~/Library/Application Support/squirrel-macos/
└── catalog/
    ├── catalog.json        # 上次拉到、验过签名的清单
    └── catalog.json.sig
```

---

## 3. 清单格式的改动

格式版本还是 1，只加字段（旧应用读不认识的字段会忽略，但旧应用不拉在线清单，影响不到）。

### 3.1 `serial`（顶层，必填）

递增的整数，用日期加序号，例如 `2026101501`。应用只接受比手头那份更大的 serial，防止有人把签过名的旧清单再塞给应用（回滚）。

### 3.2 `deprecated`（每个包，可选，默认 false）

下架一个包时不从清单里删，而是标 `deprecated: true`：已经在用的人照常能用、能更新；「添加方案」列表里不再显示；第一次打开的引导也不用它。

### 3.3 不能删、不能改 id

清单里的包 id、方案 id 一旦发布就不能删、不能改。发布脚本会和上一次发布的清单比对，发现删了或改了 id 就拒绝（见 5.1）。应用这边也有保护（见 4.3）。

### 3.4 `minAppVersion`（每个包，可选）

这个包要求的最低应用版本，例如 `"0.3.0"`。比当前应用版本高的包，读清单时直接跳过，当它不存在。

应用版本：RimeKit 里加 `AppInfo.version`（例如 `"0.3.0"`），用 [Info.plist](../../../tools/app/Info.plist) 的 `CFBundleShortVersionString`。加一个单元测试，检查两边一致，免得发版时漏改。版本号按「点分数字」逐段比较；带 `-rc` 这类后缀的版本号，只比较前面的数字部分。

---

## 4. 应用里怎么用

### 4.1 用哪份清单

手头最多有两份：

- 内置清单（随应用打包）；
- 缓存清单（`catalog/catalog.json`，上次拉到的）。

每次读缓存清单都重新验签名；验不过、读不了、格式不对，就当没有缓存，并在「诊断」页显示原因。

两份里 **serial 大的那份生效**。一样大就用内置的。应用更新后，如果内置的比缓存新，就自动用内置的。

读完以后去掉 `minAppVersion` 比当前版本高的包。如果某个保留下来的包依赖了被去掉的包，这个包也一起去掉。

现在 `Catalog.builtIn()` 在 [AppEnvironment.swift:37](../../../Sources/AppCore/AppEnvironment.swift) 和 [Rimectl.swift:66](../../../Sources/rimectl/Rimectl.swift) 两处调用，都改成调用新的 `CatalogStore.effective()`。

### 4.2 检查更新

「方案」页加按钮「检查方案清单更新」。点了以后：

1. 拉清单和签名（一次两个请求，复用现有的 `HTTPClient`，超时、429 的提示照旧）；
2. 验签名 → 解析、校验（`Catalog.validate()`）→ 比 serial → 检查兼容性（4.3）；
3. 都通过了，就写进缓存（先写临时文件再改名，不会写坏一半），以后用它。

结果有三种：

| 结果 | 提示 |
|---|---|
| 已经是最新 | 「方案清单已经是最新的」 |
| 有更新 | 说清楚变了什么：新增了哪几个方案；哪些**正在用的**包的安装规则变了；下架了哪些包 |
| 没用上 | 连不上 GitHub、签名不对、和现在的设置不兼容，各说各的原因；继续用手头那份 |

### 4.3 保护正在用的方案

新清单里如果找不到当前设置里正在用的包或方案（被删了、改了 id，或者被 `minAppVersion` 挡掉），**整份不采用**，提示「这份方案清单和你现在的设置对不上，请更新应用」。

### 4.4 规则变了要重新应用

如果更新改到了正在用的包，底部显示「有改动还没应用」，提示文字说明是方案清单更新了。点「应用改动」时，包缓存会按新规则重新整理：`PackageStore.rulesFingerprint` 已经会在规则变化时重新整理缓存。

### 4.5 什么时候自动拉一次

用户定的是「只在点按钮时拉」，只有一个例外：

- **导入时**，导出文件的设置里用到了手头清单里没有的包或方案（旧电脑拉过新清单）。导入本来就要联网下载方案，所以先拉一次清单，并在导入进度里写明「正在更新方案清单」。拉到以后还是缺，就照现在的做法报「不认识的方案」。

第一次打开的引导**不拉**：起步方案只用内置清单里的包。起步方案（[Settings.swift:86](../../../Sources/RimeKit/Config/Settings.swift)）继续写在代码里，并加一个测试，确认它们用到的方案都在内置清单里、没有标 `deprecated`。

### 4.6 联网说明

用户要求在界面上说清楚联网的事。放在两个地方：

1. **「检查方案清单更新」按钮下面**，一小段灰字：
   > 会连接 GitHub（raw.githubusercontent.com），只下载方案清单，不上传任何内容。清单带签名，验不过就不用。
2. **「诊断」页新增一节「应用什么时候会联网」**，列出全部联网操作：

   | 什么时候 | 连哪里 | 下载什么 |
   |---|---|---|
   | 安装、更新鼠须管 | GitHub（api.github.com、github.com） | 鼠须管安装包 |
   | 安装、更新方案，导入 | GitHub（api.github.com、codeload.github.com、github.com） | 方案文件 |
   | 点「检查方案清单更新」，或导入时遇到不认识的方案 | GitHub（raw.githubusercontent.com） | 方案清单 |

   最后加一句：「以上都只下载，不上传你的设置、词库、短语或文本替换。」写之前对着 `HTTPClient` 的调用核对一遍，表里的域名要和代码实际访问的一致。

   这一节下面显示当前用的是哪份清单：「内置」还是「在线（某年某月某日检查）」，以及 serial。

### 4.7 出错提示

[PackageStore.swift:30](../../../Sources/RimeKit/Packages/PackageStore.swift) 等处现在的说法是「上游方案目录结构变了，需要更新应用」，改成：

> 上游方案的目录结构变了。可以先到「方案」页点「检查方案清单更新」；还不行的话，请更新应用。

应用和 rimectl 共用这段文字。rimectl 里把「方案」页换成 `rimectl catalog check`。

### 4.8 rimectl

| 命令 | 作用 |
|---|---|
| `rimectl catalog show` | 显示正在用哪份清单（内置 / 在线）、serial、有几个包，以及缓存清单有没有问题 |
| `rimectl catalog check` | 等于点「检查方案清单更新」，打印结果和变化 |

都支持 `--data-dir`。

---

## 5. 发布清单

### 5.1 `tools/catalog/publish.sh`

1. 用 `rimectl catalog verify-source`（开发用的隐藏子命令）读正本，跑 `Catalog.validate()`，检查 `serial` 比 `catalog/v1/catalog.json` 里的大；
2. 和 `catalog/v1/catalog.json`（上一次发布的）比对：包 id、方案 id 只能增加、不能减少；不满足就拒绝；
3. 复制正本到 `catalog/v1/catalog.json`；
4. 用私钥签名，写 `catalog/v1/catalog.json.sig`；
5. 打印提示：先跑联网测试（5.3），再问用户能不能提交、推送；
6. 推送以后，可以运行 `publish.sh --verify-remote`：用 `curl` 把两个文件拉回来，用代码里的公钥再验一次。

签名由一个小的 Swift 工具做（`tools/catalog/sign`，用 CryptoKit 的 `Curve25519.Signing`），不加第三方依赖。

### 5.2 私钥

- 第一次用 `tools/catalog/keygen.sh` 生成一对密钥：私钥存进宿主机的登录钥匙串（通用密码，服务名 `squirrel-macos-catalog-signing`），公钥打印出来，写进 RimeKit 的 `CatalogSignature.publicKey`。
- 签名时用 `security find-generic-password -w` 读私钥。钥匙串可能问能不能用，点「始终允许」。
- **私钥要另外备份**（例如存进密码管理器）。丢了只能发新版应用换公钥，旧应用就再也收不到在线清单了。
- 第一版不做公钥轮换。

### 5.3 发布前要验证

- `swift test`；
- `RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests`：对内置清单里的每个包生成、编译、打字。新加的包也会被覆盖到；新方案要在测试里补一条打字检查（例如 98 五笔输入几个编码，看候选对不对）；
- 加新方案时，在测试机 `squirrel-dev` 里用新的数据目录走一遍：检查更新 → 添加 → 应用 → 打字。

### 5.4 写进 `docs/release.md`

加一节「发布方案清单」：步骤同上；写明清单的发布和应用的发布是两回事；应用发版前要确认正本已经发布（否则内置清单的 serial 会比在线的大，在线那份就不起作用了。这本身不出错，但说明漏了一步）。

---

## 6. 代码结构

RimeKit 的 `Catalog` 模块新增：

| 文件 | 内容 |
|---|---|
| `CatalogSignature.swift` | 公钥；`verify(data:signature:)` |
| `CatalogStore.swift` | 读内置和缓存、选生效的那份（4.1）；`check()` 拉取、验证、写缓存（4.2）；兼容性检查（4.3） |
| `CatalogDiff.swift` | 比较两份清单：新增的方案、规则变了的包、下架的包（4.2 的提示、4.4 的「有改动还没应用」） |
| `AppVersion.swift` | 点分版本号的比较（3.4） |

`Catalog` 加 `serial`；`PackageSpec` 加 `deprecated`、`minAppVersion`；`AppInfo` 加 `version`。

AppCore：`MainModel` 加检查更新的动作和结果；`AppEnvironment` 改用 `CatalogStore`。AppUI：`SchemasPage` 加按钮和说明；`DiagnosticsPage` 加「应用什么时候会联网」一节；「添加方案」列表过滤掉 `deprecated` 的包。

`Importer`：设置里有不认识的包或方案时，先调用 `CatalogStore.check()`（4.5）。

---

## 7. 测试

单元测试都在宿主机上跑，只用临时目录；签名测试在测试里临时生成密钥。

| 测试 | 检查什么 |
|---|---|
| 签名 | 签名对的能接受；改一个字节、签名文件缺失或乱码、换一个公钥签的，都拒绝 |
| 选哪份清单 | 缓存 serial 大用缓存；内置的大或一样大用内置；缓存损坏、签名不对时退回内置，并报原因 |
| 检查更新 | serial 不比手头大时不采用；签名不对、格式不对时不写缓存；写缓存是原子的 |
| 兼容性 | 新清单缺正在用的包或方案时不采用；`minAppVersion` 挡掉正在用的包时不采用 |
| `minAppVersion` | 比当前版本高的包被跳过；依赖它的包也被跳过；版本号比较（`0.10.0` > `0.9.0`、带 `-rc` 的） |
| `deprecated` | 不出现在添加列表；已经在用的照常生成配置 |
| 变化摘要 | 新增方案、规则变了的正在用的包、下架的包，都数对 |
| 导入 | 设置里有不认识的方案时先拉清单（`FakeHTTPClient`）；拉到以后能导入；还缺时照旧报错 |
| 起步方案 | 用到的方案都在内置清单里、没有标 `deprecated` |
| 版本号 | `AppInfo.version` 和 `tools/app/Info.plist` 一致 |
| 发布脚本的比对 | 删包、改 id、serial 没变大时拒绝 |

联网测试（`RIMEKIT_ONLINE=1 swift test --filter OnlineTests`）加一条：从 GitHub 拉真实的在线清单，用代码里的公钥验签名，serial 不小于内置的。这条能发现「忘了发布」或「签名没推上去」。

测试机（`squirrel-dev`，新的数据目录）：

- **发布前，用 rimectl**：debug 编译的 RimeKit 认两个环境变量 `RIMEKIT_CATALOG_URL`（清单地址）和 `RIMEKIT_CATALOG_TEST_PUBKEY`（多认一个测试公钥），release 编译里没有这段代码。用测试密钥签一份 serial 更大、多一个方案的清单，放在宿主机共享出去的目录里，用 `rimectl catalog check` → `settings set` → `apply` → 打字检查走一遍；再试签名不对、和设置不兼容两种情况。
- **发布第一份在线清单后，用应用**：点「检查方案清单更新」看结果和说明文字；看「诊断」页的联网说明和清单来源；把缓存清单改坏一个字节，重新打开应用，看「诊断」页报的原因、应用退回内置清单。

---

## 8. 不做

- 镜像（用户定：只用 GitHub）；
- 自动定时拉清单（用户定：只在点按钮时拉）；
- 公钥轮换；
- 清单里描述「需要新代码的能力」（用 `minAppVersion` 挡住，需要时发版）；
- 起步方案放进清单（新方案在主窗口里加就行，引导只用内置的三种起步方案）。
