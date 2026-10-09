# Configuration Reference

Xray-lite uses a JSON-based configuration file (`config.json`). Below is a detailed explanation of each section.

## Basic Structure

```json
{
  "log": {
    "level": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [...],
  "outbounds": [...]
}
```

## Inbound Object

| Field | Type | Description |
| :--- | :--- | :--- |
| `port` | `number` | The port the server listens on (e.g., 443). |
| `protocol` | `string` | Must be `"vless"`. |
| `settings` | `object` | VLESS specific settings (clients and decryption). |
| `streamSettings` | `object` | Network and security configuration. |

### VLESS Settings
- **clients**: An array of client objects.
    - **id**: A valid UUID (e.g., `"your-uuid-here"`).
    - **flow**: Leave empty or set to `"xtls-rprx-vision"` (Legacy, Reality is preferred).
- **decryption**: Usually `"none"`.

### Stream Settings
- **network**: `"tcp"` or `"xhttp"`.
- **security**: `"reality"`.
- **realitySettings**:
    - **dest**: The target website to mimic (e.g., `"www.microsoft.com:443"`).
    - **serverNames**: A list of server names (SNI) to accept (e.g., `["www.microsoft.com"]`).
    - **privateKey**: Your generated Reality private key.
    - **shortIds**: An array of hex strings used for handshake verification.

## Outbound Object

Standard outbound for proxying traffic:
```json
{
  "protocol": "freedom",
  "settings": {}
}
```

## Performance Object

Optional top-level `performance` section controlling resource usage. All fields are optional; omitted ones use the defaults below. `*Kb` fields are in KiB. See the *Memory Tuning* section in the [README](../README.md) for recommended values per memory size (64M / 128M / 256M / 512M / 1G+).

| Field | Default | Description |
| :--- | :--- | :--- |
| `workerThreads` | `0` | tokio worker threads. `0` = number of CPU cores. |
| `maxConnections` | `4096` | Maximum concurrent connections. |
| `h2StreamWindowKb` | `1024` | XHTTP: per-stream receive window (upload direction). 64 – 2097151. |
| `h2ConnectionWindowKb` | `4096` | XHTTP: per-connection receive window. 64 – 2097151. |
| `h2MaxConcurrentStreams` | `100` | XHTTP: max concurrent streams per H2 connection. |
| `h2SendBufferKb` | `256` | XHTTP: max data queued in memory per stream for sending (download direction). Minimum 32. |
| `pipeBufferKb` | `256` | XHTTP: per-stream internal VLESS pipe buffer. Minimum 16. |
| `udpSocketBufferKb` | `256` | UDP relay: send/receive buffer per UDP session socket. Minimum 32. |

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

## XDP Environment Variables

For the XDP Edition, additional parameters can be passed via command line or environment:
- `--enable-xdp`: Enable the eBPF/XDP firewall.
- `--xdp-iface`: The network interface to attach to (e.g., `eth0`).
- `--xdp-mode`: `skb` (generic) or `native` (driver-supported, faster).
