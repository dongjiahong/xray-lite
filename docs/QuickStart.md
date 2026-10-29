# Quick Start

最短上手路径。完整运维手册（文件位置、排障、升级）见仓库根目录的 [README](../README.md)。

## 1. 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)
```

交互会问四项：部署方式、端口（默认 `2083`）、伪装域名（默认 `swdist.apple.com:443`）、是否启用 XHTTP。没有 systemd 的机器会自动用手动模式。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --manual
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --systemd
```

## 2. 看状态和配置

```bash
/opt/xray-lite/manage.sh show     # 或 xray-lite show
```

输出包含运行状态、协议栈、端口、UUID、Reality、XHTTP。

## 3. 管进程

| 操作 | systemd 模式 | 手动模式 |
| :--- | :--- | :--- |
| 启动 | `systemctl start xray-lite` | `/opt/xray-lite/run.sh start` |
| 停止 | `systemctl stop xray-lite` | `/opt/xray-lite/run.sh stop` |
| 重启 | `systemctl restart xray-lite` | `/opt/xray-lite/run.sh restart` |
| 状态 | `systemctl status xray-lite` | `/opt/xray-lite/run.sh status` |
| 日志 | `journalctl -u xray-lite -f` | `/opt/xray-lite/run.sh log` |

`run.sh` 只在手动模式存在。配置相关操作两种模式都用 `manage.sh`。

## 4. 取客户端配置

```bash
scp root@<服务器IP>:/opt/xray-lite/clash-verge.yaml .    # mihomo / Clash Verge Rev
scp root@<服务器IP>:/opt/xray-lite/client-config.json .  # v2rayN / v2rayNG
```

传输方式必须和服务端一致，细节见 [Clients](./Clients.md)。

## 5. 常用配置操作

```bash
xray-lite set-port 8443               # 改端口，同步客户端配置
xray-lite set-domain www.apple.com    # 改 Reality 伪装域名
xray-lite export                      # 导出配置和 vless 链接
xray-lite rebuild                     # 清干净后完全重建
```

## 6. 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)
```

下一步：[Configuration](./Configuration.md) · [Performance](./Performance.md) · [Scripts](./Scripts.md)
