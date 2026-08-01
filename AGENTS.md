# Snell Manager 项目规则

本文件适用于本仓库及其全部子目录。开始工作前依次阅读本文件、
`README.md` 和 `STATUS.md`，再现场检查 Git 状态。

## 项目边界

- canonical repo：`/Users/shawn/Agent-Workspace/Projects/snell-manager`；
- `/Users/shawn/Dropbox/Mac (2)/Desktop/snell-manager` 是迁入前的完整来源副本，
  暂时仅作为恢复参考；未经明确批准，不删除、移动或在其中继续开发；
- 项目目标是维护 Debian 12/13 x86_64 上的 Snell v5/v6 多实例 Bash 管理器；
- 必须保持 v5/v6 的二进制、配置目录、systemd unit 和端口相互独立；
- 不自动迁移、覆盖或删除脚本发现的既有 Snell 实例；
- SSH、Tailscale、防火墙、系统网络和其他服务不在脚本管理范围内。

## Git 与授权

- 默认分支为 `main`，远端为 `https://github.com/KohSo/snell-manager.git`；
- `main` 已启用 GitHub 分支保护，修改优先在独立分支进行；
- 开始修改前至少执行 `git status --short --branch`、`git branch --show-current`
  和 `git worktree list`；
- 本地修改、commit、push、PR/merge、部署和生产环境写入是彼此独立的授权；
- 未经用户明确批准，不 commit、push、merge、发布或连接 VPS 执行变更；
- 保留用户已有的工作树修改，不清理、不覆盖无关内容。

## 安全约束

- 不在对话、测试夹具、文档、提交信息或状态文件中记录真实 PSK、私钥、
  令牌、Cookie 或其他凭据；示例只使用明显的占位值；
- 交互式配置页面按产品要求可在用户自己的终端显示完整 PSK；`--audit`
  必须继续遮盖 PSK；
- 官方包下载必须保持 HTTPS、固定版本和 SHA-256 校验；更新版本或校验值时
  需要核对官方来源并记录验证依据；
- 安装、更新和配置写入必须保留端口冲突检测、回滚、v6 `unsafe-raw`
  二次确认及部署摘要；
- 生产 VPS 上的安装、卸载、重启、配置修改和防火墙操作都需要单独授权，
  并先进行只读盘点，说明影响、验证与回滚方式。

## 实现与验证

- 代码保持兼容 Bash，延续现有函数和颜色输出风格，避免引入非必要依赖；
- 菜单与交互变更必须同时检查 v5、v6、多实例和取消/返回路径；
- 最低本地验证：

```bash
bash -n snell.sh tests/test.sh
bash tests/test.sh
git diff --check
```

- 结构或发布逻辑变更后再执行 `git fsck --full`；
- 本地 mock 测试不等同于真实 Debian VPS 安装验证。需要真实服务器验证时，
  必须使用用户批准的目标和操作范围，并保护现有实例及远程访问。

## 状态与交接

- 易变事实、当前分支、测试结果、风险和唯一下一步维护在 `STATUS.md`；
- 只有跨对话且尚未完成的复杂任务才在 `tasks/` 建立任务目录，并遵循
  `/Users/shawn/Agent-Workspace/Templates/README.md`；
- 历史迁移事实写入工作区的 `Archive/Migration-Records/`，不混入产品说明。
