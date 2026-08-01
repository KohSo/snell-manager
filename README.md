# Snell Manager

面向 Debian 12/13 的 Snell v5/v6 多实例管理脚本。它会原地识别已有 systemd 部署，不迁移旧文件；当服务器只有 v5 或 v6 时，可在独立目录和端口部署互补版本并同时运行。

## 功能

- 发现并管理不同 service、二进制和配置路径下的 Snell v5/v6。
- 主菜单按 Snell v5、Snell v6 分开管理，可独立安装、卸载、更新、启停、配置和查看状态。
- “查看当前配置”会把所有已发现实例直接输出为每实例一行的 Surge 节点。
- v5 实例同时生成原生 v5 与 v4 兼容节点；v6 节点保留实际 `mode`。
- 新增互补版本时自动检查 TCP/UDP 端口冲突，并使用独立 systemd unit。
- 新部署向导可配置服务端 TFO、DNS、v5 IPv6/HTTP OBFS，以及 v6 DNS IP 偏好/mode，并在写入前显示摘要。
- 新部署默认值跟随 xOS：端口 2345、v5/v6 PSK 分别为 16/20 位、服务端 TFO 开启、IPv6/OBFS 关闭、v6 偏好与 mode 为 `default`；端口冲突时自动改用空闲端口。
- 部署成功后立即打印可复制的 Surge 配置，默认客户端 `tfo=true, ecn=true`。
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
- 新实例按 xOS 默认生成独立的随机 PSK：v5 为 16 位，v6 为 20 位。
- 新部署不会停止现有 Snell 实例；启动失败时只清理本次新建文件。
- 旧实例不提供删除功能。只有本脚本创建的 `/etc/snell-instances/` 实例可以从菜单卸载。

## 菜单结构

```text
==============================
Snell v5/v6 多实例管理器 v1.1.0
==============================
1.管理 Snell v5
2.管理 Snell v6
3.查看 当前配置
——————————————————————————————
 00. 退出脚本
==============================

 当前状态: 已安装[v5] & [v6]且已启动

 请输入数字[0-9]:
```

进入 v5 或 v6 管理菜单后，可对该协议版本执行安装、卸载、同版本更新、启停、配置修改和状态查看；输入 `00` 返回主菜单。

## Surge 客户端参数

主菜单选择“查看当前配置”后，脚本检测公网 IPv4 并逐行打印所有实例。新部署成功后也会立即打印对应节点。

- 配置中存在服务端 `tfo` 字段时，汇总行同时输出对应 `tfo` 和默认 `ecn=true`。
- 旧配置没有 `tfo` 字段时，只输出 `reuse=true`，保留旧节点的简洁格式。
- 新部署节点按 xOS 偏好输出 `reuse=true, tfo=true, ecn=true`。

## 官方资料

- [Snell 发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- [Snell v6 设计说明](https://nssurge.com/blog/snell-v6/)

## License

MIT
