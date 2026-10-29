# Xray-Lite

A lightweight, high-performance Rust VLESS proxy with Reality & XHTTP support.

一个轻量级、高性能的纯 Rust 实现的 VLESS + Reality + XHTTP 代理服务器。不带流控，Reality + XHTTP（客户端模式选 auto）已经消除了套娃特征。

[文档索引](./docs/Home.md) | [x-ui-lite 面板](https://github.com/undead-undead/x-ui-lite) | [问题反馈](https://github.com/dongjiahong/xray-lite/issues)

---

**这份 README 是运维手册**：装什么、装完在哪、每天怎么操作、出问题先看哪里。协议原理、配置字段、性能调优、脚本内部实现都放在 `docs/`，正文对应位置有链接。

## 目录

- [快速开始](#快速开始)
- [安装](#安装)
- [装完之后：先分清两件事](#装完之后先分清两件事)
- [日常运维](#日常运维)
- [排障速查](#排障速查)
- [升级](#升级)
- [卸载](#卸载)
- [更多文档](#更多文档)
- [贡献与许可](#贡献与许可)

## 快速开始

```bash
# 1. 安装（root，交互式；没有 systemd 的机器自动用手动模式）
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)

# 2. 看当前配置（协议栈 / 端口 / UUID / Reality / XHTTP）
/opt/xray-lite/manage.sh show

# 3. 在本地取客户端配置
scp root@<服务器IP>:/opt/xray-lite/clash-verge.yaml .
```

装完确认三件事：云厂商安全组放行了端口、客户端配置导入成功、客户端和服务端传输方式一致（都用 XHTTP 或都用 TCP）。

## 安装

静态编译，x86_64 / aarch64 通用，Debian / Ubuntu / CentOS / Alpine 都不需要额外依赖。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)
```

### 交互会问什么

| 提问 | 默认值 | 说明 |
| :--- | :--- | :--- |
| 部署方式 | systemd（无 systemd 自动改手动模式） | 决定进程由谁托管，见[下一节](#装完之后先分清两件事) |
| 服务器端口 | `2083` | 装完可用 `xray-lite set-port` 改 |
| 伪装网站 | `swdist.apple.com:443` | Reality 借用的目标站，怎么选见 [Configuration](./docs/Configuration.md#reality-伪装域名怎么选) |
| 是否启用 XHTTP | `N` | 启用后还要填 path（默认 `/`）和 host（可空） |

非交互运行（`curl | bash`、CI、无 TTY）时不提问，直接用上表默认值。要覆盖就加参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --manual
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --systemd
XRAY_LITE_MEM_PROFILE=128 bash install.sh   # 指定内存档位
```

安装脚本的参数、六个执行步骤、重复运行会发生什么，见 [脚本说明](./docs/Scripts.md#installsh)。

## 装完之后：先分清两件事

### 1. 你的部署模式

装的时候选了哪种，决定你以后用什么命令管进程。不确定就跑一下这两条命令：

```bash
systemctl status xray-lite        # 有 unit = systemd 模式
ls /opt/xray-lite/run.sh          # 有这个文件 = 手动模式
```

|  | systemd 模式 | 手动模式 |
| :--- | :--- | :--- |
| 适用 | Debian / Ubuntu / CentOS 等 | Alpine 等无 systemd，或不想交给 init |
| 进程由谁托管 | systemd | `run.sh`（内部守护） |
| 日志 | `journalctl -u xray-lite` | `/opt/xray-lite/xray-lite.log` |
| 开机自启 | 自动 `enable` | 默认不会，见[开机自启](#开机自启) |
| 崩溃拉起 | systemd `Restart=on-failure` | `run.sh` 守护，3 秒后重拉 |

### 2. `manage.sh` 和 `run.sh` 各管什么

两个脚本**职责不重叠**：配置找 `manage.sh`，进程找 systemd 或 `run.sh`。

| 脚本 | 管什么 | 什么时候有 | 常用命令 |
| :--- | :--- | :--- | :--- |
| `manage.sh`（快捷命令 `xray-lite`） | **只改配置**：查看、改端口、改域名、导出、重建 | 两种模式都有 | `xray-lite show` / `set-port` / `set-domain` / `export` / `rebuild` |
| `run.sh` | **只管道进程**：启停、重启、状态、日志 | 仅手动模式生成 | `start` / `stop` / `restart` / `status` / `log` |

`manage.sh` 改完配置会自动重启服务，重启方式它自己判断（有 systemd 就用 `systemctl`，否则调 `run.sh`），你不用管。`run.sh` 不读也不改任何配置。

**按你要做的事选命令：**

| 要做的事 | systemd 模式 | 手动模式 |
| :--- | :--- | :--- |
| 启动服务 | `systemctl start xray-lite` | `/opt/xray-lite/run.sh start` |
| 停止服务 | `systemctl stop xray-lite` | `/opt/xray-lite/run.sh stop` |
| 重启服务 | `systemctl restart xray-lite` | `/opt/xray-lite/run.sh restart` |
| 看是否在运行 | `systemctl status xray-lite` | `/opt/xray-lite/run.sh status` |
| 跟日志 | `journalctl -u xray-lite -f` | `/opt/xray-lite/run.sh log` |
| 看配置、改端口、改域名、导出、重建 | `xray-lite ...` | `xray-lite ...`（同一个 `manage.sh`） |

三条规则：

1. systemd 模式**没有** `run.sh`；手动模式**不要**用 `systemctl`（unit 不存在）。
2. 不要手动 `kill vless-server`。手动模式的 `run.sh` 带守护，杀掉子进程 3 秒后会被拉起；要停就用 `run.sh stop`。
3. 配置尽量走 `manage.sh`。手改 `config.json` 不会同步客户端配置，也不会放行防火墙。

### 安装目录里都是什么

安装目录 `/opt/xray-lite/`：

| 文件 | 作用 | 备注 |
| :--- | :--- | :--- |
| `vless-server` | 服务端二进制 | 静态编译 |
| `config.json` | 服务端配置（含私钥、UUID） | 别外传 |
| `client-config.json` | Xray 系客户端配置 | v2rayN / v2rayNG 等 |
| `clash-verge.yaml` | mihomo / Clash Verge Rev 配置 | 需内核 ≥ v1.19.22 |
| `manage.sh` | 配置管理工具 | 两种模式都有 |
| `keygen` | Reality 密钥生成器 | 换密钥时用 |
| `run.sh` | 进程管理脚本 | 仅手动模式 |
| `xray-lite.pid` / `xray-lite.log` | PID / 日志 | 仅手动模式 |
| `*.bak.<时间戳>` | `manage.sh` 改动前的备份 | 可删 |

系统位置：

| 路径 | 作用 |
| :--- | :--- |
| `/etc/systemd/system/xray-lite.service` | systemd unit（仅 systemd 模式） |
| `/etc/systemd/journald.conf.d/xray-lite.conf` | 日志轮转（上限 50MB / 保留 7 天） |
| `/usr/local/bin/xray-lite` | 指向 `manage.sh` 的快捷命令（路径被占用则跳过） |

## 日常运维

### 看配置和运行状态

```bash
xray-lite show                        # 等价于 /opt/xray-lite/manage.sh show
```

输出包括：运行状态（systemd 或手动模式）、协议栈（如 `VLESS + REALITY + XHTTP`）、监听地址、端口、UUID、Reality 的 dest / serverNames / publicKey / shortIds、XHTTP 的 mode / path / host、sockopt、performance，以及两份客户端配置的端口是否与服务端一致。私钥只显示头尾。

### 改端口

```bash
xray-lite set-port 8443
```

只改监听端口，UUID / 私钥 / shortId / 传输方式都不动。脚本会：

1. 备份为 `config.json.bak.<时间戳>`，写完回读校验，失败自动还原
2. 同步 `client-config.json` 和 `clash-verge.yaml` 的节点端口（本地 socks / mixed-port 不动）
3. 放行新端口（ufw / firewalld）
4. 重启服务，并检查新端口是否在监听

加 `--no-restart` 只改文件不重启，`--no-clients` 不更新客户端配置。放行防火墙和重启服务需要 root；非 root 运行只能改文件。

端口推荐 `2083`、`8443`、`2053`、`2087`、`2096`。脚本只管本机防火墙，**云厂商安全组要自己去放行**；封的是 IP 而不是端口时，换端口没用。

### 改伪装域名

```bash
xray-lite set-domain www.apple.com          # dest 端口沿用原值（通常 443）
xray-lite set-domain www.apple.com:8443     # 显式指定 dest 端口
```

只改 `config.json` 的 `realitySettings.dest`、`serverNames`，以及客户端配置里的 `serverName` / `servername`。UUID、私钥、shortId、传输方式都不动。

目标站必须支持 TLS 1.3、HTTP/2、证书有效且从你的 VPS 能直连。换之前先在服务器上自测，候选域名和验证方法见 [Configuration](./docs/Configuration.md#reality-伪装域名怎么选)。

### 客户端配置

安装时生成两份，按客户端选一个：

| 客户端 | 用哪个文件 |
| :--- | :--- |
| Clash Verge Rev / mihomo | `clash-verge.yaml` |
| v2rayN / v2rayNG / 其他 Xray 系 | `client-config.json` |

```bash
scp root@<服务器IP>:/opt/xray-lite/clash-verge.yaml .
```

**服务端和客户端的传输方式必须一致**：服务端启用 XHTTP，客户端也必须用 XHTTP。mihomo 的 xhttp 需要内核 ≥ v1.19.22。细节和 `vless://` 链接格式见 [客户端配置](./docs/Clients.md)。

改过端口或域名后，重新 `scp` 一份，或者直接 `xray-lite export` 导出。

### 导出配置

```bash
xray-lite export                      # 导出到 ~/xray-lite-export-<时间戳>/
xray-lite export /root/out --tar      # 指定目录并打包
```

会打印现成的 `scp` 命令和 `vless://` 链接。导出的 `config.json` 含私钥，别提交到公开仓库。

### 重启、日志、开机自启

| 操作 | systemd 模式 | 手动模式 |
| :--- | :--- | :--- |
| 重启 | `systemctl restart xray-lite` | `/opt/xray-lite/run.sh restart` |
| 跟日志 | `journalctl -u xray-lite -f` | `/opt/xray-lite/run.sh log` |
| 最近 50 行 | `journalctl -u xray-lite -n 50 --no-pager` | `tail -n 50 /opt/xray-lite/xray-lite.log` |

#### 开机自启

systemd 模式安装时已 `enable`，不用管。手动模式默认不会自启，Alpine 上加一次：

```bash
echo '/opt/xray-lite/run.sh start' > /etc/local.d/xray-lite.start
chmod +x /etc/local.d/xray-lite.start
rc-update add local default
```

### 内存不够 / 被 OOM 杀掉

大流量下载在 64MB 级小机器或容器里可能被 OOM。先从日志确认：

```bash
dmesg -T | grep -i -E 'killed process|out of memory'
```

然后按机器内存调小 `config.json` 的 `performance` 段，重启生效。`install.sh` 已经按内存自动选了一档，手动改法、各档位配置、容器注意事项见 [性能与内存调优](./docs/Performance.md#内存调优小内存--容器)。

### 升级

只换二进制，保留现有配置（推荐）：

```bash
systemctl stop xray-lite          # 手动模式用 /opt/xray-lite/run.sh stop

curl -fsSL "https://github.com/dongjiahong/xray-lite/releases/download/<版本>/xray-linux-amd64" \
  -o /opt/xray-lite/vless-server
chmod +x /opt/xray-lite/vless-server

systemctl start xray-lite         # 手动模式用 /opt/xray-lite/run.sh start
xray-lite show                    # 确认配置没丢
```

aarch64 机器的资产名不同（安装脚本用 `vless-server-linux-aarch64`），以 Releases 页面为准。

重跑 `install.sh` 会重新生成 UUID 和密钥，客户端要重新导入，升级前先 `cp /opt/xray-lite/config.json ~/`。想连旧残留一起清掉就用 `xray-lite rebuild`，它会在重装前备份配置，执行细节见 [脚本说明](./docs/Scripts.md#rebuild)。

## 排障速查

| 现象 | 先做什么 | 详情 |
| :--- | :--- | :--- |
| 服务起不来 | 看日志：`journalctl -u xray-lite -n 50` 或 `/opt/xray-lite/run.sh log` | [服务起不来](#服务起不来) |
| 客户端连不上，日志只有 `📥 新连接来自` | `xray-lite show` 看传输方式，确认客户端一致 | [客户端配置](./docs/Clients.md) |
| 换端口后仍不通 | 检查云厂商安全组是否放行 TCP 新端口 | [改端口](#改端口) |
| 换域名后握手失败 | 在服务器上 `curl` 自测目标站 | [Configuration](./docs/Configuration.md#reality-伪装域名怎么选) |
| 内存持续上涨 / 进程消失 | 确认是否 OOM，调小 `performance` | [Performance](./docs/Performance.md#内存调优小内存--容器) |
| `xray-lite` 命令不存在 | 用 `/opt/xray-lite/manage.sh`，或手动建软链 | [快捷命令没了](#快捷命令没了) |

### 服务起不来

```bash
journalctl -u xray-lite -n 50 --no-pager      # systemd
/opt/xray-lite/run.sh log                      # 手动模式
```

常见原因：端口被占用、UUID 格式不对、`performance` 取值越界、Reality 字段为空。

手动模式下如果启动 3 秒内就退出，守护不会无限重启，这是有意的：说明是配置或端口问题，重启也没用。

端口被占用又找不到进程（Alpine 没有 `pkill`）：

```bash
kill $(pidof vless-server)
# 或者 apk add procps 后用 pkill -f vless-server
```

### 快捷命令没了

安装时 `/usr/local/bin/xray-lite` 已存在同名文件会被跳过。直接用 `/opt/xray-lite/manage.sh`，或手动建软链：

```bash
ln -sf /opt/xray-lite/manage.sh /usr/local/bin/xray-lite
```

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)
```

默认先把 `config.json` 和两份客户端配置备份到 `~/xray-lite-backup-<时间戳>/`，再删除。可选参数：

| 参数 | 作用 |
| :--- | :--- |
| `--purge` | 不备份，直接删除 |
| `--remove-firewall` | 一并删除安装时添加的 ufw / firewalld 端口规则 |

两种部署模式都能卸载：会停 systemd 服务、结束手动模式进程、删安装目录、日志轮转配置和快捷命令。

## 更多文档

| 文档 | 内容 |
| :--- | :--- |
| [QuickStart](./docs/QuickStart.md) | 最短上手路径 |
| [Configuration](./docs/Configuration.md) | `config.json` 字段、Reality 伪装域名选择 |
| [Clients](./docs/Clients.md) | mihomo / Xray 客户端配置与常见坑 |
| [Performance](./docs/Performance.md) | 系统调优、`performance` 各内存档位、容器内存 |
| [Protocols](./docs/Protocols.md) | VLESS + Reality、XHTTP 的反探测机制 |
| [XDP Features](./docs/XDP_Features.md) | XDP 版的内核层防护（独立分支） |
| [Scripts](./docs/Scripts.md) | 四个脚本的参数、内部步骤与设计取舍 |
| [Development](./docs/Development.md) | 从源码构建、发布流程 |

## 贡献与许可

We welcome all kinds of contributions! Please verify that `cargo test` passes before submitting a PR.
欢迎各种形式的贡献！提交 PR 前请确保通过 `cargo test`。构建方法见 [Development](./docs/Development.md)。

[MPL-2.0](LICENSE)
