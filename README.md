# Snell Manager

面向 Debian 12/13 的 Snell v5/v6 多实例管理脚本。它会原地识别已有 systemd 部署，不迁移旧文件；当服务器只有 v5 或 v6 时，可在独立目录和端口部署互补版本并同时运行。

## 功能

- 发现并管理不同 service、二进制和配置路径下的 Snell v5/v6。
- 查看配置、生成 Surge 节点行、启停、重启、状态、日志和配置修改。
- 新增互补版本时自动检查 TCP/UDP 端口冲突，并使用独立 systemd unit。
- 配置修改、二进制更新和新实例安装均带回滚保护。
- `--audit` 只读审计默认遮盖 PSK。
- Snell v5 服务端向下兼容 v4 客户端，无需单独安装 v4 服务端。

## 支持范围

- Debian 12 / 13
- x86_64
- systemd
- Snell v5.0.1 与官方 Snell v6.0.0rc 包

脚本不会修改 SSH、Tailscale、Nginx、系统时区或全局 sysctl。已有部署原地管理，不会被自动重命名或覆盖。

## 安装与运行

```bash
wget -O snell.sh https://raw.githubusercontent.com/KohSo/snell-manager/main/snell.sh
chmod +x snell.sh
sudo ./snell.sh
```

只读审计：

```bash
sudo ./snell.sh --audit
```

## 安全行为

- 首页、审计和日志输出遮盖 PSK；只有明确进入“查看配置”时显示完整 PSK。
- 下载仅使用 Surge 官方 HTTPS 地址，并核对固定 SHA-256。
- 新实例默认生成独立的 32 位随机 PSK。
- 新部署不会停止现有 Snell 实例；启动失败时只清理本次新建文件。
- 旧实例不提供删除功能。只有本脚本创建的 `/etc/snell-instances/` 实例可以从菜单卸载。

## 官方资料

- [Snell 发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- [Snell v6 设计说明](https://nssurge.com/blog/snell-v6/)

## License

MIT
