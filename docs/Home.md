# Welcome to Xray-Lite Wiki

Xray-lite is a lightweight, high-performance VLESS + Reality proxy server implemented in pure Rust. It is designed for users who prioritize performance, memory efficiency, and advanced stealth capabilities.

## Architecture Highlights

- **Pure Rust Implementation**: High performance with memory safety.
- **Asymmetric Compatibility**: Works with standard Xray/V2Ray clients (v2rayNG, Shadowsocks-libev, etc.).
- **Kernel-Level Acceleration**: Uses eBPF (XDP/TC) for firewalling and traffic shaping (XDP Edition).
- **Stealth First**: Optimized for Reality and xhttp protocols to evade detection.

## Navigation

- [Quick Start Guide](./QuickStart.md)
- [Configuration Reference](./Configuration.md)
- [Client Setup](./Clients.md)
- [Core Protocols (Reality, xhttp, XTLS-Reality64)](./Protocols.md)
- [Performance & Memory Tuning](./Performance.md)
- [Scripts (install / manage / run / uninstall)](./Scripts.md)
- [Building from Source](./Development.md)
- [XDP & Kernel Defense](./XDP_Features.md)

运维操作（安装、日常命令、排障、升级）见仓库根目录的 [README](../README.md)。

## Why Xray-Lite?

Unlike official Xray which handles everything in user-space, Xray-lite moves critical network operations into the Linux kernel (via XDP). This not only boosts performance by reducing context switching but also provides a "stealth" layer where certain probing packets are dropped before they even reach the application layer.
