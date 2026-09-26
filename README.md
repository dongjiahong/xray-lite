# Xray-Lite

A lightweight, high-performance Rust VLESS proxy with Reality & XHTTP support.

一个轻量级、高性能的纯 Rust 实现的 VLESS + Reality + xhttp 代理服务器。【特别说明：不带流控，Reality + xhttp(客户端模式选auto)已经消除了套娃特征】

[Documentation](./docs/Home.md) | [x-ui-lite Panel](https://github.com/undead-undead/x-ui-lite) | [Report Bug](https://github.com/dongjiahong/xray-lite/issues)



## Quick Installation / 快速安装

> **Note**: This is a **static compilation version** that works perfectly on **any Linux system** (Debian, Ubuntu, CentOS, Alpine, etc.) without dependency issues.
>
> **注意**：此为**静态编译版本**，完美适配**任何 Linux 系统** (Debian, Ubuntu, CentOS, Alpine 等)，无需担心依赖问题。

### Installation / 安装

> **Current Version: v0.4.7**

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
