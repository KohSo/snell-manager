# Snell Manager 当前状态

> 最后核实：2026-08-01（Asia/Shanghai）  
> 本文件记录易变事实；接手时仍须以现场 Git 和测试结果为准。

## 仓库状态

- canonical repo：`/Users/shawn/Agent-Workspace/Projects/snell-manager`
- 远端：`origin = https://github.com/KohSo/snell-manager.git`
- 默认分支：`main`
- 当前整理分支：`agent/workspace-onboarding`
- 迁入基线：`cc37961005e4cbadbe2604e04e18aaedd663df47`
- 工作树：整理文档提交后应为 clean；没有产品代码改动

## 已完成状态

- GitHub PR #2 已合并到 `main`，合并结果即上述迁入基线；
- `main` 已启用分支保护：禁止 force push 和删除，要求通过 PR 合并并解决
  conversation；当前未配置 CI required status checks；
- Snell v5/v6 多实例管理、xOS 风格安装交互、菜单排版、配置展示和 Surge
  节点生成已进入 `main`；
- README 已包含对 xOS/Snell 的致谢和独立项目声明；
- 迁入前已知本地测试结果为 113 项通过；本次迁入后的复核结果见下方。

## 当前边界与风险

- 尚未在一次性 Debian VPS 上完成完整安装、更新、回滚和卸载流程验证；
- 官方 Snell 版本与下载包可能变化，发布前应重新核对版本和 SHA-256；
- 交互页面按用户选择明文显示 PSK，`--audit` 仍应保持遮盖；
- 原 Dropbox 仓库保留作恢复参考，不在两个副本中并行开发；
- 本次整理仅获授权 commit 并 push 当前整理分支，不包含 PR、merge、VPS
  连接或部署授权。

## 本次验证

- `bash -n snell.sh tests/test.sh` 通过；
- `bash tests/test.sh`：113 项全部通过；
- `git diff --check` 通过；
- `git fsck --full` 通过；
- 本地 `HEAD` 与远端 `main` 均为
  `cc37961005e4cbadbe2604e04e18aaedd663df47`；
- 未进行真实 VPS 安装测试。

## 唯一下一步

按需审阅已推送的整理分支，再单独决定是否建立 PR 并合入 `main`。
