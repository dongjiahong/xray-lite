# 从源码构建

需要 Rust 工具链。仓库内已包含 `rustls-reality` 的本地 patch，直接构建即可。

```bash
cargo build --release
```

产物：

| 文件 | 作用 |
| :--- | :--- |
| `target/release/vless-server` | 服务端 |
| `target/release/keygen` | Reality 密钥对生成器 |
| `target/release/genconfig` | 打印一份示例配置 |

`keygen` 生成 Reality 密钥对，`genconfig` 输出可直接参考的配置样例。

## 测试

提交 PR 前先跑：

```bash
cargo test
```

## 发布构建

`release_build.sh` 负责跨平台静态发布，需要 `x86_64-unknown-linux-musl` target 和 eBPF 子目录，仅维护者发布时使用。

```bash
./release_build.sh
```

返回 [README](../README.md) | 脚本参数见 [Scripts](./Scripts.md)。
