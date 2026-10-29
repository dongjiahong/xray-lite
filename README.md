# Xray-Lite

A lightweight, high-performance Rust VLESS proxy with Reality & XHTTP support.

一个轻量级、高性能的纯 Rust 实现的 VLESS + Reality + xhttp 代理服务器。【特别说明：不带流控，Reality + xhttp(客户端模式选 auto) 已经消除了套娃特征】

[Documentation](./docs/Home.md) | [x-ui-lite Panel](https://github.com/undead-undead/x-ui-lite) | [Report Bug](https://github.com/dongjiahong/xray-lite/issues)

---

**本文是运维视角的说明**：装完之后文件在哪、每个脚本怎么用、出问题先看哪里。协议与调优细节见 `docs/`。

## 目录

- [快速开始](#快速开始)
- [安装](#安装)
- [安装后：文件都在哪](#安装后文件都在哪)
- [日常操作速查](#日常操作速查)
- [脚本参数参考](#脚本参数参考)
- [排障](#排障)
- [升级](#升级)
- [内存调优](#内存调优)
- [客户端配置](#客户端配置)
- [从源码构建](#从源码构建)
- [Contributing / License](#contributing--license)

## 快速开始

```bash
# 1. 安装（root，交互式）
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)

# 2. 看当前配置（协议栈 / 端口 / UUID / Reality / XHTTP）
/opt/xray-lite/manage.sh show

# 3. 取客户端配置
scp root@<服务器IP>:/opt/xray-lite/clash-verge.yaml .
```

安装后只做三件事就能用：确认端口已放行 → 下载客户端配置 → 导入客户端。

## 安装

静态编译，x86_64 / aarch64 通用，Debian / Ubuntu / CentOS / Alpine 都不需要额外依赖。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)
```

### 安装时会问什么

| 提问 | 默认值 | 说明 |
| :--- | :--- | :--- |
| 部署方式 | systemd（无 systemd 则自动用手动模式） | 决定进程由谁托管，见下方对照 |
| 服务器端口 | `443` | 之后可随时用 `manage.sh set-port` 改 |
| 伪装网站 | `www.microsoft.com:443` | Reality 借用的目标站，填 `域名:443` |
| 是否启用 XHTTP | `N` | 启用后还要填 path（`/`）和 host（可空） |

非交互运行（`curl \| bash`、CI、无 TTY）时不会提问，直接使用上表默认值；需要覆盖就加参数或环境变量。

### 两种部署方式

| | `systemd service`（默认） | `manual run` |
| :--- | :--- | :--- |
| 适用 | Debian / Ubuntu / CentOS 等 | Alpine 等无 systemd，或不想交给 init |
| 管理 | `systemctl start/stop/restart/status xray-lite` | `/opt/xray-lite/run.sh start/stop/restart/status/log` |
| 日志 | `journalctl -u xray-lite -f` | `/opt/xray-lite/xray-lite.log` |
| 开机自启 | 自动（`enable`） | 默认不会，需自己加 |
| 崩溃拉起 | systemd `Restart=on-failure` | `run.sh` 内置守护，3 秒后重拉 |

没有 `systemctl` 的环境会**自动**切到手动模式，不会生成 systemd unit 和 journald 轮转配置。手动模式日志超过 10MB 时，下次启动会轮转为 `xray-lite.log.1`。

Alpine 上要开机自启：

```bash
echo '/opt/xray-lite/run.sh start' > /etc/local.d/xray-lite.start
chmod +x /etc/local.d/xray-lite.start
rc-update add local default
```

### 跳过交互 / 指定部署方式

```bash
# 直接指定部署方式
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --manual
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --systemd

# 或者用环境变量
XRAY_LITE_DEPLOY=manual bash install.sh
XRAY_LITE_MEM_PROFILE=128 bash install.sh   # 指定内存档位
```

### 安装脚本会做的事

1. 检测架构（x86_64 / aarch64），停掉旧服务和残留进程
2. 从 GitHub Releases 下载 `vless-server`、`keygen`、`manage.sh`
3. 生成 Reality 密钥对、UUID、shortId，按可用内存写入 `performance` 段
4. 写出 `config.json` 和两份客户端配置
5. 安装 systemd 服务（或 `run.sh`），配置 journald 日志轮转
6. 放行端口（ufw / firewalld），检查端口占用，启动服务

## 安装后：文件都在哪

安装目录 `/opt/xray-lite/`：

| 文件 | 作用 | 备注 |
| :--- | :--- | :--- |
| `vless-server` | 服务端二进制 | 静态编译 |
| `config.json` | 服务端配置（含私钥、UUID） | 别外传 |
| `client-config.json` | Xray 系客户端配置 | v2rayN / v2rayNG 等 |
| `clash-verge.yaml` | mihomo / Clash Verge Rev 配置 | 需内核 ≥ v1.19.22 |
| `manage.sh` | 管理工具（看配置 / 改端口） | 见下节 |
| `keygen` | Reality 密钥生成器 | 改密钥时用 |
| `run.sh` | 手动模式管理脚本 | 仅手动模式 |
| `xray-lite.pid` | 手动模式 PID | 仅手动模式 |
| `xray-lite.log` | 手动模式日志 | 仅手动模式 |
| `*.bak.<时间戳>` | `manage.sh` 改动前的备份 | 可删 |

系统位置：

| 路径 | 作用 |
| :--- | :--- |
| `/etc/systemd/system/xray-lite.service` | systemd unit（仅 systemd 模式） |
| `/etc/systemd/journald.conf.d/xray-lite.conf` | 日志轮转（上限 50MB / 保留 7 天） |
| `/usr/local/bin/xray-lite` | 指向 `manage.sh` 的快捷命令（若该路径已被占用则跳过） |

## 日常操作速查

```bash
# —— 看配置 ——
xray-lite show                        # 装了快捷命令
/opt/xray-lite/manage.sh show         # 没装快捷命令时用这个

# —— 改端口（UUID / 密钥 / 传输方式保持不变）——
xray-lite set-port 8443

# —— 服务管理（systemd）——
systemctl status xray-lite
systemctl restart xray-lite
journalctl -u xray-lite -f

# —— 服务管理（手动模式）——
/opt/xray-lite/run.sh status
/opt/xray-lite/run.sh restart
/opt/xray-lite/run.sh log

# —— 客户端配置 ——
scp root@<服务器IP>:/opt/xray-lite/clash-verge.yaml .

# —— 卸载 ——
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)
```

`show` 的输出包含：协议栈（如 `VLESS + REALITY + XHTTP`）、监听地址、端口、UUID、Reality 的 dest / serverNames / publicKey / shortIds、XHTTP 的 mode / path / host、sockopt、performance，以及两份客户端配置的端口是否与服务端一致。私钥只显示头尾。

`set-port` 只改 `config.json` 第一个入站的 `port`，并会：

1. 先备份为 `config.json.bak.<时间戳>`，写完回读校验，失败自动还原
2. 同步 `client-config.json`（只改 vnext 端口，本地 socks 1080 不动）
3. 同步 `clash-verge.yaml`（只改节点端口，`mixed-port` / DNS 不动）
4. 放行新端口（ufw / firewalld，需 root）
5. 重启服务并检查新端口是否在监听

## 脚本参数参考

### `install.sh`

| 参数 / 环境变量 | 作用 |
| :--- | :--- |
| `--systemd` | 强制安装为 systemd 服务 |
| `--manual` | 强制使用 `run.sh` 手动模式 |
| `XRAY_LITE_DEPLOY=systemd\|manual` | 同上，环境变量形式 |
| `XRAY_LITE_MEM_PROFILE=64\|128\|256\|512\|1024` | 指定 `performance` 档位，跳过自动探测 |
| `-h`, `--help` | 查看用法 |

要求 root。重复运行会**重新生成 `config.json`**（换新 UUID / 密钥），升级前务必先备份。端口和 XHTTP 的选择在交互模式下每次都会重新询问。

### `manage.sh`（`xray-lite` 命令）

| 命令 / 参数 | 作用 |
| :--- | :--- |
| `show` | 打印当前配置（默认命令，可省略） |
| `set-port <端口>` | 只改监听端口，其它字段原样保留 |
| `-c`, `--config PATH` | 指定 `config.json`，默认 `/opt/xray-lite/config.json` |
| `XRAY_LITE_CONFIG=PATH` | 同上，环境变量形式 |
| `--no-restart` | 只改文件不重启 |
| `--no-clients` | 不更新两份客户端配置 |
| `-h`, `--help` | 查看用法 |

已经装好的机器想补这个脚本，不用重装：

```bash
curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/manage.sh -o /opt/xray-lite/manage.sh
chmod +x /opt/xray-lite/manage.sh
ln -sf /opt/xray-lite/manage.sh /usr/local/bin/xray-lite   # 可选
```

### `run.sh`（仅手动模式）

| 命令 | 作用 |
| :--- | :--- |
| `start` | 后台启动（带守护，崩溃后 3 秒重拉） |
| `stop` | 停止 |
| `restart` | 重启 |
| `status` | 查看是否在运行 |
| `log` | `tail -f` 日志 |

### `uninstall.sh`

| 参数 | 作用 |
| :--- | :--- |
| 无 | 备份配置到 `~/xray-lite-backup-<时间戳>/`，再卸载 |
| `--purge` | 不备份，直接删除 |
| `--remove-firewall` | 一并删除安装时添加的 ufw / firewalld 端口规则 |

默认保留防火墙放行规则。两种部署模式都能卸载：会停 systemd 服务、清掉手动模式进程、删除安装目录、日志轮转配置和快捷命令。

### `vless-server`（直接运行）

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `-c`, `--config` | `config.json` | 配置文件路径 |
| `-l`, `--log-level` | `info` | `trace` / `debug` / `info` / `warn` / `error` |
| `RUST_LOG` | — | 环境变量，优先级高于 `--log-level` |

## 排障

**连不上，服务端日志只有 `📥 新连接来自` 就没下文**

服务端和客户端的传输方式不一致，最常见。`manage.sh show` 看协议栈：带 `XHTTP` 就必须用 xhttp 客户端配置；不带就是 tcp。另外 mihomo 的 xhttp 需要内核 ≥ v1.19.22，低版本会把未知 `network` 当 tcp 处理。

**端口被封 / 换了端口还是不通**

```bash
xray-lite set-port 8443
```

脚本只处理本机防火墙。云厂商的**安全组 / 控制台防火墙**要自己去放行 `TCP 新端口`。如果封的是 IP 而不是端口，换端口无效。常用备选：`8443`、`2053`、`2083`、`2087`、`2096`、`8080`。

**服务起不来**

```bash
journalctl -u xray-lite -n 50 --no-pager      # systemd
/opt/xray-lite/run.sh log                      # 手动模式
```

先看是不是端口被占用、配置校验失败（UUID 格式、`performance` 取值越界、Reality 字段为空）。手动模式下如果启动 3 秒内就退出，守护不会无限重启，这是有意的。

**端口被占用，Alpine 上没有 pkill**

```bash
kill $(pidof vless-server)
# 或者 apk add procps 后用 pkill -f vless-server
```

**内存持续上涨 / 被 OOM 杀掉**

调小 `config.json` 的 `performance` 段，见[内存调优](#内存调优)。`podman inspect --format '{{.State.OOMKilled}}' <容器>` 可以确认是否被 OOM。

**`xray-lite` 命令不存在**

安装时 `/usr/local/bin/xray-lite` 已存在同名文件会被跳过，直接用 `/opt/xray-lite/manage.sh`，或者手动建软链。

**改了端口，客户端没跟着变**

`set-port` 会同步同目录下的两份客户端配置；如果你用 `--no-clients`、或者客户端配置在别处，需要自己改。`show` 会标出端口不一致。

## 升级

两种方式，按需要选：

**只换二进制（保留现有配置，推荐）**

```bash
systemctl stop xray-lite          # 手动模式用 /opt/xray-lite/run.sh stop

# 从 Releases 下载对应架构的 vless-server（当前 x86_64 资产名为 xray-linux-amd64）
curl -fsSL "https://github.com/dongjiahong/xray-lite/releases/download/<版本>/xray-linux-amd64" \
  -o /opt/xray-lite/vless-server
chmod +x /opt/xray-lite/vless-server

systemctl start xray-lite
xray-lite show                    # 确认配置仍符合预期
```

这种方式不会动 `config.json`，UUID、密钥、端口都保留。

**重跑 `install.sh`（会重新生成配置）**

```bash
cp /opt/xray-lite/config.json ~/config.json.backup
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)
```

重跑会得到新的 UUID、密钥和客户端配置，客户端需要重新导入。想保留旧参数，就在装完后手工把 `performance` 等段落合并回去。

## 内存调优

小内存机器（64MB 级、容器里加了内存上限）上，大流量长时间下载可能让进程被 OOM 杀掉。v0.4.8 起：

- XHTTP 下行加入了**真正的反压**：客户端收得慢时，服务端会停止读取目标服务器，内存不再随下载量无限增长。（旧版本是把数据一直堆在 h2 发送缓冲里直到 OOM。）
- 所有和内存相关的开关都放到了 `config.json` 的 `performance` 段，可以按机器大小调整。
- `install.sh` 会读取内存（容器里优先取 cgroup 限制），自动选一档写进 `config.json`；可用 `XRAY_LITE_MEM_PROFILE=64|128|256|512|1024` 手动指定。
- 手动运行模式的 `run.sh` 现在带守护：进程被 OOM 杀掉或崩溃后 3 秒自动拉起（启动 3 秒内就退出，说明是配置/端口问题，不会无限重启）。

### `performance` 参数

整段可省略，省略时使用默认值（约等于下面的 256M 档）。只写需要改的字段即可，没写的保持默认。单位 `Kb` 均为 KiB。

| 字段 | 默认 | 作用 | 调小的代价 |
| :--- | :--- | :--- | :--- |
| `workerThreads` | `0`（按 CPU 核数） | tokio 工作线程数 | 单核满载时吞吐受限 |
| `maxConnections` | `4096` | 最大并发连接数，超过后排队等待 | 并发多时新连接被拖慢 |
| `h2StreamWindowKb` | `1024` | XHTTP 每个流的接收窗口（影响**上传**方向） | 上传速度受限 |
| `h2ConnectionWindowKb` | `4096` | XHTTP 每个 H2 连接的接收窗口，应不小于流窗口 | 同上 |
| `h2MaxConcurrentStreams` | `100` | 单个 H2 连接最大并发流数 | 客户端并发请求被限制 |
| `h2SendBufferKb` | `256` | **每个流**最多在内存里排队等发送的下行数据，最关键的一项 | 单流下载速度受限（高延迟链路更明显） |
| `pipeBufferKb` | `256` | 每个流内部 VLESS 管道的缓冲 | 吞吐略降 |
| `udpSocketBufferKb` | `256` | 每个 UDP 会话 socket 的收发缓冲（QUIC/视频） | UDP 突发时丢包 |

粗略估算：最坏内存 ≈ 4~10MB（进程基础）+ 同时在下载的流数 × (`h2SendBufferKb` + `pipeBufferKb` + 64KB 读缓冲)。

### 不同内存的推荐配置

把对应档位整段加到 `config.json` 顶层（和 `inbounds`、`outbounds` 同级），然后重启。

**64M**（单核小鸡/容器，少量并发）

```json
"performance": {
  "workerThreads": 1,
  "maxConnections": 256,
  "h2StreamWindowKb": 256,
  "h2ConnectionWindowKb": 512,
  "h2MaxConcurrentStreams": 32,
  "h2SendBufferKb": 64,
  "pipeBufferKb": 64,
  "udpSocketBufferKb": 64
}
```

**128M**

```json
"performance": {
  "workerThreads": 2,
  "maxConnections": 512,
  "h2StreamWindowKb": 512,
  "h2ConnectionWindowKb": 2048,
  "h2MaxConcurrentStreams": 64,
  "h2SendBufferKb": 128,
  "pipeBufferKb": 128,
  "udpSocketBufferKb": 128
}
```

**256M**

```json
"performance": {
  "workerThreads": 2,
  "maxConnections": 1024,
  "h2StreamWindowKb": 1024,
  "h2ConnectionWindowKb": 4096,
  "h2MaxConcurrentStreams": 100,
  "h2SendBufferKb": 256,
  "pipeBufferKb": 256,
  "udpSocketBufferKb": 256
}
```

**512M**

```json
"performance": {
  "workerThreads": 0,
  "maxConnections": 4096,
  "h2StreamWindowKb": 2048,
  "h2ConnectionWindowKb": 8192,
  "h2MaxConcurrentStreams": 128,
  "h2SendBufferKb": 512,
  "pipeBufferKb": 512,
  "udpSocketBufferKb": 512
}
```

**1G 及以上**

```json
"performance": {
  "workerThreads": 0,
  "maxConnections": 8192,
  "h2StreamWindowKb": 4096,
  "h2ConnectionWindowKb": 16384,
  "h2MaxConcurrentStreams": 256,
  "h2SendBufferKb": 1024,
  "pipeBufferKb": 1024,
  "udpSocketBufferKb": 1024
}
```

启动日志会打印生效的参数（`⚙️ 性能参数`），确认改动是否生效。取值不合法（比如 `h2SendBufferKb` 小于 32）会在启动时报错并退出。

### Alpine / Podman 容器注意事项

- 容器内 `/proc/meminfo` 显示的是**宿主机**内存，真正的上限是容器的 cgroup 限制，例如 `podman run --memory=64m --memory-swap=64m ...`（`--memory-swap` 与 `--memory` 相同即不用 swap）。
- 内核里 TCP/UDP 的 socket 缓冲也计入容器的内存上限，所以并发连接多时，除了进程自身的内存，还要给内核缓冲留余量。64M 档建议同时保持较小的 `maxConnections`。
- 是否被 OOM 杀过：`podman inspect --format '{{.State.OOMKilled}}' <容器>`，或在宿主机上 `dmesg -T | grep -i -E 'killed process|out of memory'`。
- 观察实际占用：`podman stats <容器>`。下载时内存应稳定在一个值附近，不再持续上涨。

## 客户端配置

**服务端和客户端的传输方式必须一致**，不一致的表现是服务端日志里只有 `📥 新连接来自` 之后就没有下文。`install.sh` 会按你选的传输方式生成匹配的配置：

| 服务端 | mihomo (`clash-verge.yaml`) | Xray 客户端 |
| :--- | :--- | :--- |
| 启用 XHTTP | `network: xhttp` + `alpn: [h2]` + `xhttp-opts` | `"network": "xhttp"` |
| 未启用 XHTTP | `network: tcp` | `"network": "tcp"` |

两个容易踩的坑：

- mihomo 的 xhttp 传输需要内核 **≥ v1.19.22**（Clash Verge Rev 的设置页能看到内核版本）。低版本内核会把未知的 `network` 值当 tcp 处理，于是连不上。
- mihomo **没有** `spider-x` 字段，那是 Xray 的概念，写进 YAML 会被静默忽略。

Xray 系客户端也可以直接用链接导入，结构如下：

```
vless://<uuid>@<ip>:<port>?security=reality&sni=<serverName>&fp=chrome&pbk=<publicKey>&sid=<shortId>&type=tcp&encryption=none#Xray-Lite
```

启用 XHTTP 时把 `type=tcp` 换成对应的 xhttp 参数，具体值以 `client-config.json` 为准。

## 从源码构建

需要 Rust 工具链，仓库内已包含 `rustls-reality` 的本地 patch。

```bash
cargo build --release
# 产物
# target/release/vless-server
# target/release/keygen
# target/release/genconfig
```

`keygen` 生成 Reality 密钥对，`genconfig` 打印一份示例配置。跨平台静态发布由 `release_build.sh` 负责（需要 `x86_64-unknown-linux-musl` target 和 eBPF 子目录，仅维护者发布时使用）。

## Contributing / License

We welcome all kinds of contributions! Please verify that `cargo test` passes before submitting a PR.
欢迎各种形式的贡献！提交 PR 前请确保通过 `cargo test`。

[MPL-2.0](LICENSE)
