# Xray-Lite

A lightweight, high-performance Rust VLESS proxy with Reality & XHTTP support. Powered by eBPF kernel-level XDP Firewall for ultimate stealth.

一个轻量级、高性能的纯 Rust 实现的 VLESS + Reality + xhttp 代理服务器。基于 eBPF 技术的 XDP 内核防火墙，实现极致隐身与安全。【特别说明：不带流控，Reality + xhttp(客户端模式选auto)已经消除了套娃特征】

[Documentation](./docs/Home.md) | [x-ui-lite Panel](https://github.com/undead-undead/x-ui-lite) | [Report Bug](https://github.com/dongjiahong/xray-lite/issues)



## Quick Installation / 快速安装

> **Note**: This is a **static compilation version** that works perfectly on **any Linux system** (Debian, Ubuntu, CentOS, Alpine, etc.) without dependency issues.
>
> **注意**：此为**静态编译版本**，完美适配**任何 Linux 系统** (Debian, Ubuntu, CentOS, Alpine 等)，无需担心依赖问题。

### 1. Standard Installation (Recommended) / 标准版安装（推荐）

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

### 2. 🔴 **[XDP Installation (Performance Enhanced) / XDP 版安装（性能增强版）](https://github.com/undead-undead/xray-lite/blob/main/docs/XDP_Features.md)**

> ⚠️ XDP 分支只存在于上游仓库，本 fork 未包含。

> **Kernel Recommendations / 内核达标推荐**: 
> - **Optimal (最佳)**: Linux Kernel **≥ 5.15** (e.g., Ubuntu 22.04+, Debian 12+) - *Full XDP support.*
> - **Minimum (最低)**: Linux Kernel **≥ 5.4** - *Basic XDP support.*
> - **Note**: AMD64 Architecture & Root privileges required.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/undead-undead/xray-lite/feature/dynamic-xdp/install.sh)
```

### Deployment Verification / 部署验证

```bash
# Verify XDP Attachment / 验证 XDP 挂载
ip link show eth0
# Output: prog/xdp id 366 tag 480c33de76109440 jited
```

![XDP Success Verification](docs/assets/xdp_success.png)

## Client Configuration / 客户端配置

**服务端和客户端的传输方式必须一致**，不一致的表现是服务端日志里只有 `📥 新连接来自` 之后就没有下文。`install.sh` 会按你选的传输方式生成匹配的配置：

| 服务端 | mihomo (`clash-verge.yaml`) | Xray 客户端 |
| :--- | :--- | :--- |
| 启用 XHTTP | `network: xhttp` + `alpn: [h2]` + `xhttp-opts` | `"network": "xhttp"` |
| 未启用 XHTTP | `network: tcp` | `"network": "tcp"` |

两个容易踩的坑：

- mihomo 的 xhttp 传输需要内核 **≥ v1.19.22**（Clash Verge Rev 的设置页能看到内核版本）。低版本内核会把未知的 `network` 值当 tcp 处理，于是连不上。
- mihomo **没有** `spider-x` 字段，那是 Xray 的概念，写进 YAML 会被静默忽略。

## Graphical Panel / 图形化面板

[x-ui-lite](https://github.com/undead-undead/x-ui-lite) is a lightweight web panel designed specifically for Xray-lite.
- **Hot Reload**: Supports seamless configuration updates without service interruption.
- **Easy Management**: Visualize your traffic, manage clients, and monitor XDP stats.

[x-ui-lite](https://github.com/undead-undead/x-ui-lite) 是专为 Xray-lite 设计的轻量化面板。
- **热重载支持**：配置变更即时生效，无需重启服务。
- **便捷管理**：可视化流量统计、客户端管理及 XDP 内核防火墙状态监控。





If you think the project is good, you can support the developers.


https://buymeacoffee.com/undeadundead


crypto:

Sol: 9QFKQ3jpBSuNPLZQH1uq5GrJm4RDKue82zeVaXwazcmj


Base：0x4cf0b79aea1c229dfb1df9e2b40ea5dd04f37969


## Contributing / 贡献

We welcome all kinds of contributions! Please verify that `cargo test` passes before submitting a PR.
欢迎各种形式的贡献！提交 PR 前请确保通过 `cargo test`。

## License / 许可证

[MPL-2.0](LICENSE)
