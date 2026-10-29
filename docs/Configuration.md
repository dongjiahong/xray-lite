# Configuration Reference

Xray-lite uses a JSON-based configuration file (`config.json`). Below is a detailed explanation of each section.

## Basic Structure

```json
{
  "inbounds": [ ... ],
  "outbounds": [ ... ],
  "routing": { "rules": [] },
  "performance": { ... }
}
```

`routing` 和 `performance` 可省略。日志级别由启动参数控制（`-l` / `RUST_LOG`），不在 `config.json` 里配。

## Inbound Object

| Field | Type | Description |
| :--- | :--- | :--- |
| `listen` | `string` | 监听地址，通常 `"0.0.0.0"`。 |
| `port` | `number` | 监听端口（如 `2083`）。 |
| `protocol` | `string` | 必须是 `"vless"`。 |
| `settings` | `object` | VLESS 相关设置（clients / decryption / sniffing）。 |
| `streamSettings` | `object` | 传输与安全设置。 |

### VLESS Settings
- **clients**: An array of client objects.
    - **id**: A valid UUID (e.g., `"your-uuid-here"`).
    - **flow**: Leave empty or set to `"xtls-rprx-vision"` (Legacy, Reality is preferred).
- **decryption**: Usually `"none"`.

### Stream Settings
- **network**: `"tcp"` 或 `"xhttp"`。
- **security**: `"reality"`（也支持 `none` / `tls`）。
- **realitySettings**:
    - **dest**: 伪装目标站，例如 `"www.apple.com:443"`。
    - **serverNames**: 接受的 SNI 列表，例如 `["www.apple.com", "*.www.apple.com"]`。
    - **privateKey** / **publicKey**: Reality 密钥对。
    - **shortIds**: 握手校验用的 hex 字符串数组。
    - **fingerprint**: 默认 `"chrome"`。
- **xhttpSettings**（仅 `network` 为 `xhttp` 时）:
    - **mode**: `auto` / `stream-up` / `stream-down` / `stream-one`，默认 `auto`。
    - **path**: 默认 `"/"`。
    - **host**: 默认空（表示任意）。
- **sockopt**:
    - **tcpFastOpen** / **tcpNoDelay**: 默认 `true`。
    - **acceptProxyProtocol**: 默认 `false`。

## Outbound Object

Standard outbound for proxying traffic:
```json
{
  "protocol": "freedom",
  "settings": {}
}
```

## Performance Object

Optional top-level `performance` section controlling memory and concurrency. All fields are optional; omitted ones use defaults (roughly the 256M profile). `*Kb` fields are KiB.

Field reference, per-memory presets (64M / 128M / 256M / 512M / 1G+), and container notes are in [Performance Tuning](./Performance.md#performance-参数).

## Reality 伪装域名怎么选

Reality 的伪装目标站必须同时满足：**支持 TLS 1.3、支持 HTTP/2、证书有效且与域名匹配、从你的 VPS 能直接访问**。任选其一，换之前先自测。

| 域名 | 说明 |
| :--- | :--- |
| `swdist.apple.com` | 安装脚本默认值 |
| `addons.mozilla.org` | |
| `assets.unicornplatform.net` | |
| `s0.awsstatic.com` | |
| `speed.cloudflare.com` | |

在服务器上验证（四项都过了再用）：

```bash
for d in swdist.apple.com addons.mozilla.org assets.unicornplatform.net s0.awsstatic.com speed.cloudflare.com; do
    printf '%-32s ' "$d"
    curl -sI --tlsv1.3 --http2 --max-time 5 "https://$d" \
        -o /dev/null -w 'HTTP/%{http_version} %{http_code}\n' || echo "不可用"
done
```

输出 `HTTP/2 200`（或 30x / 40x，只要是 HTTP/2 且有响应）就说明可用。全部失败说明这台机器到目标站不通，换个域名或换个站。

换域名用 `xray-lite set-domain <域名>[:端口]`，它会同步服务端和客户端。具体改动范围和失败回滚见 [Scripts](./Scripts.md#set-domain)。

## XDP Environment Variables

For the XDP Edition, additional parameters can be passed via command line or environment:
- `--enable-xdp`: Enable the eBPF/XDP firewall.
- `--xdp-iface`: The network interface to attach to (e.g., `eth0`).
- `--xdp-mode`: `skb` (generic) or `native` (driver-supported, faster).
