# Xray-Lite

A lightweight, high-performance Rust VLESS proxy with Reality & XHTTP support.

一个轻量级、高性能的纯 Rust 实现的 VLESS + Reality + xhttp 代理服务器。【特别说明：不带流控，Reality + xhttp(客户端模式选auto)已经消除了套娃特征】

[Documentation](./docs/Home.md) | [x-ui-lite Panel](https://github.com/undead-undead/x-ui-lite) | [Report Bug](https://github.com/dongjiahong/xray-lite/issues)



## Quick Installation / 快速安装

> **Note**: This is a **static compilation version** that works perfectly on **any Linux system** (Debian, Ubuntu, CentOS, Alpine, etc.) without dependency issues.
>
> **注意**：此为**静态编译版本**，完美适配**任何 Linux 系统** (Debian, Ubuntu, CentOS, Alpine 等)，无需担心依赖问题。

### Installation / 安装

> **Current Version: v0.4.8**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)
```

安装脚本会询问端口和是否启用 XHTTP，装完在 `/opt/xray-lite/` 下生成**两份客户端配置**，直接取下来导入即可：

| 文件 | 用途 |
| :--- | :--- |
| `clash-verge.yaml` | Clash Verge Rev / mihomo，导入即用（需内核 ≥ v1.19.22） |
| `client-config.json` | Xray 系客户端（v2rayN / v2rayNG 等） |

```bash
scp root@<你的服务器IP>:/opt/xray-lite/clash-verge.yaml .
```

### Deployment Mode / 部署方式

安装时会问你用哪种方式托管进程：

| 方式 | 适用 | 管理 |
| :--- | :--- | :--- |
| `systemd service`（默认） | Debian / Ubuntu / CentOS 等有 systemd 的系统 | `systemctl start/stop/restart/status xray-lite`，日志 `journalctl -u xray-lite -f` |
| `manual run` | Alpine 等无 systemd 的系统，或不想交给 init 托管 | `/opt/xray-lite/run.sh start/stop/restart/status/log`，日志写 `/opt/xray-lite/xray-lite.log` |

- 没有 `systemctl` 的环境**自动**切到手动运行模式，不会再生成 systemd unit 和 journald 轮转配置。
- 手动模式用 `nohup` 后台运行，PID 记在 `/opt/xray-lite/xray-lite.pid`；日志超过 10MB 会在下次启动时轮转为 `xray-lite.log.1`（无 journald 就没有系统级轮转，只能这样兜底）。
- 手动模式**不会开机自启**。Alpine 上要自启：

```bash
echo '/opt/xray-lite/run.sh start' > /etc/local.d/xray-lite.start
chmod +x /etc/local.d/xray-lite.start
rc-update add local default
```

跳过交互直接指定部署方式：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh) --manual
# 或者用环境变量 / or via env
XRAY_LITE_DEPLOY=systemd curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh | bash
```

`uninstall.sh` 两种模式都能卸：它会停掉 systemd 服务、`pkill` 掉手动模式起的进程，再删掉安装目录（含 `run.sh` 与日志）。

## Memory Tuning / 内存调优

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
- 已安装的老版本升级：重新运行 `install.sh` 会重新生成 `config.json`（请先备份）；或者只下载新二进制，在现有 `config.json` 里手动加上面的 `performance` 段，再 `/opt/xray-lite/run.sh restart`。

## Uninstall / 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)
```

默认会先把 `config.json`（含 Reality 私钥与 UUID）和两份客户端配置备份到 `~/xray-lite-backup-<时间戳>/`，再停服务、删安装目录、清理日志轮转配置；防火墙放行规则默认保留。

| 选项 | 作用 |
| :--- | :--- |
| `--purge` | 不备份配置，直接删除 |
| `--remove-firewall` | 一并删除安装时添加的 ufw / firewalld 端口放行规则 |

## Client Configuration / 客户端配置

**服务端和客户端的传输方式必须一致**，不一致的表现是服务端日志里只有 `📥 新连接来自` 之后就没有下文。`install.sh` 会按你选的传输方式生成匹配的配置：

| 服务端 | mihomo (`clash-verge.yaml`) | Xray 客户端 |
| :--- | :--- | :--- |
| 启用 XHTTP | `network: xhttp` + `alpn: [h2]` + `xhttp-opts` | `"network": "xhttp"` |
| 未启用 XHTTP | `network: tcp` | `"network": "tcp"` |

两个容易踩的坑：

- mihomo 的 xhttp 传输需要内核 **≥ v1.19.22**（Clash Verge Rev 的设置页能看到内核版本）。低版本内核会把未知的 `network` 值当 tcp 处理，于是连不上。
- mihomo **没有** `spider-x` 字段，那是 Xray 的概念，写进 YAML 会被静默忽略。


## Contributing / 贡献

We welcome all kinds of contributions! Please verify that `cargo test` passes before submitting a PR.
欢迎各种形式的贡献！提交 PR 前请确保通过 `cargo test`。

## License / 许可证

[MPL-2.0](LICENSE)
