# 上游包的目录结构

实测：2026-10-15，测试机 `squirrel-dev`，用 `curl` 下载、`/usr/bin/ditto -x -k` 解压。只记结构，不复制文件内容。阶段 1 写 `catalog.json` 时以这里为准。

## 极点五笔 86：`KyleBing/rime-wubi86-jidian`

- 下载：`https://codeload.github.com/KyleBing/rime-wubi86-jidian/zip/refs/heads/master`（约 1.9 MB）。不发 Release，版本用提交号（GitHub API `repos/KyleBing/rime-wubi86-jidian/commits/master` 的 `sha`）。
- 顶层目录：`rime-wubi86-jidian-master/`（**带分支名**，换分支或用标签下载时会变，要用 `find` 定位）。
- 共 25 个文件。

| 类别 | 文件 |
|---|---|
| 方案 | `wubi86_jidian.schema.yaml`、`wubi86_jidian_pinyin.schema.yaml`、`wubi86_jidian_trad.schema.yaml`、`wubi86_jidian_trad_pinyin.schema.yaml`、`pinyin_simp.schema.yaml`、`numbers.schema.yaml` |
| 词库 | `wubi86_jidian.dict.yaml`、`wubi86_jidian_extra.dict.yaml`、`wubi86_jidian_extra_district.dict.yaml`、`pinyin_simp.dict.yaml` |
| 个人词库模板（**个人内容，更新时不能覆盖用户的**） | `wubi86_jidian_user.dict.yaml`、`wubi86_jidian_user_hamster.dict.yaml` |
| 上游自带补丁（当默认值读入，不直接复制） | `default.custom.yaml`、`squirrel.custom.yaml` |
| 不需要装的 | `weasel.custom.yaml`（Windows 用）、`README.md`、`LICENSE`、`.github/`、`.gitignore`、`imgs/`、`plum/`、`仓键盘布局/`、`wubi86_jidian.ico` |

没有 Lua、没有 OpenCC。

## 雾凇拼音完整方案：`iDvel/rime-ice` 的 `full.zip`

- 下载：`https://github.com/iDvel/rime-ice/releases/download/nightly/full.zip`（约 16 MB）。版本用 Release 附件的 `updated_at`（GitHub API `repos/iDvel/rime-ice/releases/tags/nightly`），当前是 2026-10-05。
- **没有顶层目录**，文件直接在 zip 根上。共 70 个文件。

| 类别 | 文件 |
|---|---|
| 方案 | `rime_ice.schema.yaml`（全拼）、`double_pinyin_flypy.schema.yaml`（小鹤）以及另外 6 个双拼、`t9.schema.yaml`、`melt_eng.schema.yaml`、`radical_pinyin.schema.yaml` |
| 词库 | `rime_ice.dict.yaml`、`cn_dicts/`（`8105`、`41448`、`base`、`ext`、`others`、`tencent`）、`en_dicts/`、`melt_eng.dict.yaml`、`radical_pinyin.dict.yaml` |
| Lua | `lua/`（约 30 个 `.lua` 文件、`lua/cold_word_drop/` 子目录、`lunar.db`）。**没有 `rime.lua`**（用新写法直接引用 `lua/` 里的模块） |
| OpenCC | `opencc/`（`emoji.json`、`emoji.txt`、`others.txt`） |
| **会顶替鼠须管自带设置的文件** | `default.yaml`、`squirrel.yaml`（和鼠须管自带的同名；按 Rime 的查找规则用户目录优先，没有单独实测）、`symbols_v.yaml`、`symbols_caps_v.yaml` |
| **自带的短语文件** | `custom_phrase.txt`（上游自带的默认短语）。和应用要生成的 `custom_phrase.txt` **同名冲突**，阶段 2 设计生成规则时要处理（合并上游的和用户的，或者让用户的短语用另一个文件名） |
| 不需要装的 | `weasel.yaml`（Windows 用）、`LICENSE`（保留在缓存里供展示） |

## 雾凇词库：`iDvel/rime-ice` 的 `cn_dicts.zip`

- 下载：`https://github.com/iDvel/rime-ice/releases/download/nightly/cn_dicts.zip`（约 14.7 MB）。版本同上，用附件的 `updated_at`。
- 顶层目录：`cn_dicts/`，里面 6 个 `.dict.yaml`（`8105`、`41448`、`base`、`ext`、`others`、`tencent`）。解压后路径是 `cn_dicts/cn_dicts/…`（解压到同名目录时会多一层）。
- 极点五笔的「拼音词库 = 雾凇」只用 `8105`、`base`、`ext`。同样的文件在 `full.zip` 的 `cn_dicts/` 里也有，所以同时装了雾凇全拼时可以不再单独下载。
