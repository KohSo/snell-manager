# Snell Manager

面向 Debian 12/13 的 Snell v5/v6 多实例管理脚本。它会原地识别已有 systemd 部署，不迁移旧文件；当服务器只有 v5 或 v6 时，可在独立目录和端口部署互补版本并同时运行。

## 功能

- 发现并管理不同 service、二进制和配置路径下的 Snell v5/v6。
- 查看配置、交互生成 Surge 节点行、启停、重启、状态、日志和配置修改。
- v5 实例同时生成原生 v5 与 v4 兼容节点；v6 节点保留实际 `mode`。
- 客户端 TFO 与 ECN 分别询问并按 xOS 偏好默认开启，不与服务端 `tfo` 混为一个开关。
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

## Surge 客户端参数

进入实例菜单后选择“生成 Surge 客户端配置”。脚本会检测公网 IPv4，也允许手动输入域名或 IPv6。

- `tfo=true` 和 `ecn=true` 是 Surge 客户端参数，由生成向导分别询问。
- 服务端配置中的 `tfo = true` 是独立开关，不会自动强制客户端开启 TFO。
- `ecn` 按 xOS 偏好默认开启；向导会提示不支持 ECN 的网络可能连接失败。
- `reuse=true` 按 xOS 的输出偏好加入 v5、v4 兼容和 v6 节点。

## 官方资料

- [Snell 发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- [Snell v6 设计说明](https://nssurge.com/blog/snell-v6/)

## License

MIT
