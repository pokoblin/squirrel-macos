# 阶段 0 验证记录

日期：2026-10-15。环境：Tart 测试机 `squirrel-dev`（从 `macos-base` 克隆，macOS 27.0.1），宿主机 macOS 27.0.1。

| # | 验证项 | 结论 | 详情 |
|---|---|---|---|
| 1 | 系统设置键盘页链接 | | |
| 2 | 授权弹窗安装时 postinstall 拿到桌面用户 | | |
| 3 | 独立 .app 读文本替换数据库 | | |
| 4 | `ditto` 解压 GitHub zip | | |
| 5 | 鼠须管运行时 `rime_dict_manager` 导出/合并 | | |
| 6 | 雾凇全拼、小鹤双拼在鼠须管 1.1.2 上部署和打字 | | |

## 宿主机

- TRProbe（本机临时签名、未授权的独立 app，用 `open` 启动）：`path_exists=true`、`readable=true`、`open_rc=0`、`count=11`，**没有弹出权限对话框**，能直接读。
- `rime-type-probe` 在参考配置（`../squirrel-wubi86/rime` 副本）上：`g` → 一、`weixin` → 微信、`qukuailian` → 区块链、`neijuan` → 内卷，全部正确。日志显示 librime 加载了 `lua` 模块（插件在工具里也能加载）。

## 过程
