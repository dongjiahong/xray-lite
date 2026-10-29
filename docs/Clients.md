# 客户端配置

服务端装好后，`install.sh` 会在 `/opt/xray-lite/` 生成两份客户端配置，按你用的客户端选一个。

| 客户端 | 用哪个文件 | 传输方式字段 |
| :--- | :--- | :--- |
| Clash Verge Rev / mihomo | `clash-verge.yaml` | `network: xhttp` 或 `tcp` |
| v2rayN / v2rayNG / 其他 Xray 系 | `client-config.json` | `"network": "xhttp"` 或 `"tcp"` |

```bash
scp root@<服务器IP>:/opt/xray-lite/clash-verge.yaml .
# 或
scp root@<服务器IP>:/opt/xray-lite/client-config.json .
```

不想手动取文件，可以在服务器上跑 `xray-lite export`，它会导出两份配置加一个 `vless-link.txt`，并打印现成的 `scp` 命令。

## 传输方式必须一致

**服务端和客户端的传输方式不一致，是连不上的头号原因。** 表现是服务端日志里只有 `📥 新连接来自`，之后没有下文。

用 `xray-lite show` 看协议栈：

- 带 `XHTTP` → 客户端也必须用 XHTTP
- 不带 → 用 TCP 配置

| 服务端 | mihomo (`clash-verge.yaml`) | Xray 客户端 |
| :--- | :--- | :--- |
| 启用 XHTTP | `network: xhttp` + `alpn: [h2]` + `xhttp-opts` | `"network": "xhttp"` |
| 未启用 XHTTP | `network: tcp` | `"network": "tcp"` |

两个容易踩的坑：

- mihomo 的 xhttp 传输需要内核 **≥ v1.19.22**（Clash Verge Rev 设置页能看到内核版本）。低版本内核会把未知的 `network` 值当 tcp 处理，于是连不上。
- mihomo **没有** `spider-x` 字段，那是 Xray 的概念，写进 YAML 会被静默忽略。

## 用链接导入

Xray 系客户端也可以直接导入 `vless://` 链接，`xray-lite export` 生成的 `vless-link.txt` 就是现成的。结构如下：

```
vless://<uuid>@<ip>:<port>?security=reality&sni=<serverName>&fp=chrome&pbk=<publicKey>&sid=<shortId>&type=tcp&encryption=none#Xray-Lite
```

启用 XHTTP 时把 `type=tcp` 换成对应的 xhttp 参数，具体值以 `client-config.json` 为准。

## 改端口 / 改域名之后

`xray-lite set-port` 和 `xray-lite set-domain` 会同步同目录下的两份客户端配置。但如果你用了 `--no-clients`，或客户端配置早就拷到别处，需要自己改：

- 端口：改节点里的 `port`
- 域名：改 Reality 的 `serverName`（mihomo 为 `servername`）

改完重新 `scp` 或 `xray-lite export` 一份，`xray-lite show` 会标出客户端和服务端端口是否一致。

返回 [README](../README.md) | 服务端字段见 [Configuration](./Configuration.md)。
