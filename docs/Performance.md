# 性能与内存调优

Xray-Lite 默认配置已经面向小机器优化，下面这些是进一步压榨性能或在小内存机器上保命时用的。

## 系统限制（ulimit）

高并发时先确认文件描述符够用：

```bash
ulimit -n 65535
```

或写进 `/etc/security/limits.conf`：

```text
* soft nofile 65535
* hard nofile 65535
```

## 缓冲区

v0.4.6+ 默认使用 512KB 双工缓冲和 8KB+ 分块，已在 CPU 唤醒次数和内存占用之间取过平衡，通常不需要改。

## XDP native 模式

网卡驱动支持时用 `native` 模式，省掉一次 SKB 拷贝：

```bash
./vless-server -c config.json --enable-xdp --xdp-iface eth0 --xdp-mode native
```

XDP 版的要求与能力见 [XDP Features](./XDP_Features.md)。

## 资源占用参考

面向入门级 VPS（1 vCPU / 512MB–1GB）优化：

| 指标 | 1 vCPU / 1GB |
| :--- | :--- |
| 空闲内存 | < 6MB |
| 高负载内存 | < 20MB（零拷贝） |
| 1Gbps 吞吐（标准版） | 约 25% CPU |
| 1Gbps 吞吐（XDP native） | 约 10% CPU |

## 内存调优（小内存 / 容器）

小内存机器（64MB 级、容器里加了内存上限）做大流量长时间下载，进程可能被 OOM 杀掉。v0.4.8 起：

- XHTTP 下行加入了**真正的反压**：客户端收得慢时，服务端停止读取目标服务器，内存不再随下载量无限增长。（旧版本会把数据一直堆在 h2 发送缓冲里直到 OOM。）
- 所有和内存相关的开关都在 `config.json` 的 `performance` 段，可按机器大小调整。
- `install.sh` 会读取内存（容器里优先取 cgroup 限制），自动选一档写进 `config.json`；也可用 `XRAY_LITE_MEM_PROFILE=64|128|256|512|1024` 手动指定。
- 手动模式的 `run.sh` 带守护：进程被 OOM 杀掉或崩溃后 3 秒自动拉起（启动 3 秒内就退出说明是配置/端口问题，不会无限重启）。

### `performance` 参数

整段可省略，省略时使用默认值（约等于 256M 档）。只写需要改的字段即可。单位 `Kb` 均为 KiB。

| 字段 | 默认 | 作用 | 调小的代价 |
| :--- | :--- | :--- | :--- |
| `workerThreads` | `0`（按 CPU 核数） | tokio 工作线程数 | 单核满载时吞吐受限 |
| `maxConnections` | `4096` | 最大并发连接数，超过后排队等待 | 并发多时新连接被拖慢 |
| `h2StreamWindowKb` | `1024` | XHTTP 每个流的接收窗口（影响**上传**方向） | 上传速度受限 |
| `h2ConnectionWindowKb` | `4096` | XHTTP 每个 H2 连接的接收窗口，应不小于流窗口 | 同上 |
| `h2MaxConcurrentStreams` | `128` | 单个 H2 连接最大并发流数 | 客户端并发请求被限制 |
| `h2SendBufferKb` | `256` | **每个流**最多在内存里排队等发送的下行数据，最关键的一项 | 单流下载速度受限（高延迟链路更明显） |
| `pipeBufferKb` | `256` | 每个流内部 VLESS 管道的缓冲 | 吞吐略降 |
| `udpSocketBufferKb` | `256` | 每个 UDP 会话 socket 的收发缓冲（QUIC / 视频） | UDP 突发时丢包 |

粗略估算：最坏内存 ≈ 4~10MB（进程基础）+ 同时在下载的流数 × (`h2SendBufferKb` + `pipeBufferKb` + 64KB 读缓冲)。

### 不同内存的推荐配置

把对应档位整段加到 `config.json` 顶层（和 `inbounds`、`outbounds` 同级），然后重启。

**64M**（单核小鸡 / 容器，少量并发）

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

- 容器内 `/proc/meminfo` 显示的是**宿主机**内存，真正的上限是 cgroup，例如 `podman run --memory=64m --memory-swap=64m ...`（`--memory-swap` 与 `--memory` 相同即不用 swap）。
- 内核里 TCP/UDP 的 socket 缓冲也计入容器内存上限。并发连接多时，除了进程自身内存，还要给内核缓冲留余量；64M 档建议同时保持较小的 `maxConnections`。
- 是否被 OOM 杀过：`podman inspect --format '{{.State.OOMKilled}}' <容器>`，或在宿主机上 `dmesg -T | grep -i -E 'killed process|out of memory'`。
- 观察实际占用：`podman stats <容器>`。下载时内存应稳定在一个值附近，不再持续上涨。

返回 [README](../README.md) | 配置字段见 [Configuration](./Configuration.md)。
