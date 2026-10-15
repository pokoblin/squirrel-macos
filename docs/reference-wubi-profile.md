# 样板 Profile：五笔 + 拼音混输 + 雾凇词库

这是我（项目作者）实际在用的一套配置，来自上一个项目 squirrel-wubi86（完整配置文件备份在那个项目的 `rime/` 目录）。用来说明“一个五笔用户的 Profile 需要包含什么”，也是将来做“导入现有配置”和“内置模板”的第一个测试样本。

## 用到的上游包

| 包 | 版本 | 用到的部分 |
|---|---|---|
| `KyleBing/rime-wubi86-jidian` | 提交 `18a6016`（2026-10-10） | 全部 `.yaml`：五笔码表、5 个五笔方案、`pinyin_simp`、`numbers`，以及它自带的 `default.custom.yaml`、`squirrel.custom.yaml` |
| `iDvel/rime-ice` | 提交 `da1fbe6`（2026-10-05） | 只用 `cn_dicts/` 里的 `8105`、`base`、`ext` 三个词库（不用它的方案） |
| 鼠须管 | 1.1.2 | — |

## 在上游基础上做的改动

### 方案列表和默认方案（`default.custom.yaml`）

```yaml
schema_list:
  - schema: wubi86_jidian_pinyin      # 五笔拼音混输（默认，排第一）
  - schema: wubi86_jidian             # 五笔
  - schema: numbers                   # 大写数字
  - schema: wubi86_jidian_trad        # 五笔 - 简入繁出
  - schema: wubi86_jidian_trad_pinyin # 五笔拼音混输 - 简入繁出
  - schema: pinyin_simp               # 普通拼音
```

- 上游默认第一位是纯五笔。纯五笔打拼音不出字，很容易被误以为“没装好”。改成拼音混输排第一。
- 其它保持上游：每页 5 个候选、`Control+0` 切换方案、Shift 提交编码、Emacs 风格的编辑键等。

### 翻页键（`default.custom.yaml`）

打开了上游注释掉的两行，和 macOS 自带五笔一致：

```yaml
- { when: has_menu, accept: minus, send: Page_Up }
- { when: has_menu, accept: equal, send: Page_Down }
```

（`[` `]`、Tab 翻页是上游本来就有的。）

### 外观（`squirrel.custom.yaml`）

- 配色：浅色 `roseo_maple`，深色 `roseo_maple_dark`（上游默认）。
- 字号：候选字 `font_point` 18 → **24**；序号 `label_font_point` 17 → **20**；注释 `comment_font_point` 16 → **20**。**浅色和深色两套都改了。**
- 注意：这个上游把字号、横排竖排等样式写在每个配色方案里面（`preset_color_schemes.<配色>.font_point`），不是写在全局 `style` 里。文件里还有 `candidate_font_point`，那个是**无效键名**，改了没用。

### 换拼音词库：新建总词库 `pinyin_ext.dict.yaml`

```yaml
name: pinyin_ext
sort: by_weight
import_tables:
  - pinyin_user       # 个人拼音词（最前面，优先）
  - cn_dicts/8105     # 雾凇：字表
  - cn_dicts/base     # 雾凇：基础词库
  - cn_dicts/ext      # 雾凇：扩展词库
```

没用雾凇的 `tencent` 词库（约 100 万条，没有拼音列，部署很慢）。

### 让各方案改用新词库，并加上自定义短语

5 个补丁文件，**不改上游原文件**：

| 文件 | 改什么 |
|---|---|
| `pinyin_simp.custom.yaml` | `translator/dictionary: pinyin_ext` |
| `wubi86_jidian.custom.yaml`、`wubi86_jidian_pinyin.custom.yaml`、`wubi86_jidian_trad.custom.yaml`、`wubi86_jidian_trad_pinyin.custom.yaml`（4 个内容相同） | `reverse_lookup/dictionary: pinyin_ext` |

这 5 个文件还都加了自定义短语：

```yaml
"engine/translators/@before 0": table_translator@custom_phrase
custom_phrase:
  dictionary: ""
  user_dict: custom_phrase
  db_class: stabledb
  enable_completion: false
  enable_sentence: false
  initial_quality: 100
```

### 个人内容

| 文件 | 内容 | 导出时 |
|---|---|---|
| `wubi86_jidian_user.dict.yaml` | 个人五笔词（上游自带的空模板，已挂在五笔主码表上） | 用户选择 |
| `pinyin_user.dict.yaml` | 个人拼音词（自己新建，挂在 `pinyin_ext` 最前面） | 用户选择 |
| `custom_phrase.txt` | 从 macOS「文本替换」生成，11 条 | **不导出**（隐私；新电脑重新生成） |

⚠️ 上游更新时，会用自己的空模板覆盖 `wubi86_jidian_user.dict.yaml`。前端必须把这个文件当“个人内容”单独保存，不能当上游文件处理。

## 不该进 Profile 的东西

| 文件 | 原因 |
|---|---|
| `build/` | 部署时自动生成 |
| `installation.yaml` | 本机的安装编号 |
| `user.yaml` | 本机状态（上次部署时间、上次选的方案） |
| `*.userdb` | 输入习惯数据库，二进制，跨电脑直接拷容易出问题（要不要随 Profile 迁移，待确认） |
| `weasel.custom.yaml` | Windows 小狼毫用的，Mac 上没用 |

## 验证结果（这套配置在全新虚拟机里恢复后实际打字）

| 输入 | 结果 |
|---|---|
| `g` | 一（五笔） |
| `weixin` | 微信（拼音混输） |
| `qukuailian` | 区块链（雾凇新词，旧词库里没有） |
| 候选字大小 | 24 号 ✅ |

之前用 librime 模拟验证过的（宿主机配置副本，拼音混输方案）：

| 输入 | 换词库前 | 换词库后 |
|---|---|---|
| `neijuan` | 内圈 内眷 | **内卷** 内眷 |
| `tangping` | 无候选 | 躺平 烫平 |
| `yuanyuzhou` | 无候选 | 元宇宙 |
| `yyz`（简拼） | — | 有一种 有意者 抑郁症… |
