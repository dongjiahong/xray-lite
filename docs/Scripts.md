# 脚本说明

仓库有四个运维脚本，职责不重叠：

| 脚本 | 跑在哪 | 职责 | 日常要不要用 |
| :--- | :--- | :--- | :--- |
| `install.sh` | 安装 / 重建时 | 下载二进制、生成密钥与配置、装服务、放行端口 | 安装或重建时 |
| `manage.sh` | 装完后一直用 | 看配置、改端口、改域名、导出、重建 | 改配置时 |
| `run.sh` | 仅手动模式 | 起停、重启、状态、日志 | 手动模式管进程时 |
| `uninstall.sh` | 卸载时 | 备份并删除安装 | 卸载时 |

`manage.sh` 和 `run.sh` 的分工与选择，见 [README 的决策表](../README.md#2-managesh-和-runsh-各管什么)。

## install.sh

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)
```

要求 root。安装目录固定 `/opt/xray-lite/`。

### 参数

| 参数 / 环境变量 | 作用 |
| :--- | :--- |
| `--systemd` | 强制安装为 systemd 服务 |
| `--manual` | 强制使用 `run.sh` 手动模式 |
| `XRAY_LITE_DEPLOY=systemd\|manual` | 同上，环境变量形式 |
| `XRAY_LITE_MEM_PROFILE=64\|128\|256\|512\|1024` | 指定 `performance` 档位，跳过自动探测 |
| `-h`, `--help` | 查看用法 |

没有 `systemctl` 的机器会**自动**切到手动模式，不会生成 systemd unit 和 journald 轮转配置。显式传了 `--systemd` 但系统没有 systemd 时，会提示后回退到手动模式。

### 执行步骤

1. 检测架构（x86_64 / aarch64），停掉上一次安装留下的进程
2. 从 GitHub Releases 下载 `vless-server`、`keygen`，从仓库下载 `manage.sh`
3. 生成 Reality 密钥对、UUID、shortId，按可用内存写入 `performance` 段
4. 写出 `config.json`、`client-config.json`、`clash-verge.yaml`
5. 安装 systemd 服务（或生成 `run.sh`），配置 journald 日志轮转
6. 放行端口（ufw / firewalld），检查端口占用，启动服务

### 重复运行的代价

`install.sh` 会**重新生成 `config.json`**（新 UUID、新密钥、新 shortId），不是原地升级。想保留现有配置就只替换二进制，见 README 的[升级](../README.md#升级)。装完会留一份 `install.sh` 在安装目录，供 `manage.sh rebuild` 离线复用。

## manage.sh

两种模式都有，快捷命令 `/usr/local/bin/xray-lite`（安装时若路径被占用则跳过）。不传子命令等同 `show`。

### 命令

| 命令 / 参数 | 作用 |
| :--- | :--- |
| `show` | 打印当前配置（默认命令，可省略） |
| `set-port <端口>` | 只改监听端口，其它字段原样保留 |
| `set-domain <域名>[:端口]` | 只改 Reality 的 dest / serverNames，其它字段原样保留 |
| `export [目录]` | 导出配置文件，打印 scp 命令和 VLESS 链接 |
| `rebuild` | 完全重建：清干净旧残留后重新安装 |
| `-c`, `--config PATH` | 指定 `config.json`，默认 `/opt/xray-lite/config.json` |
| `XRAY_LITE_CONFIG=PATH` | 同上，环境变量形式 |
| `--no-restart` | 只改文件不重启 |
| `--no-clients` | 不更新两份客户端配置 |
| `--tar` | `export` 时额外打包为 `tar.gz` |
| `-y`, `--yes` | `rebuild` 时跳过确认 |
| `--installer PATH` | `rebuild` 时使用指定的 `install.sh` |
| `-h`, `--help` | 查看用法 |

已经装好的机器想补这个脚本，不用重装：

```bash
curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/manage.sh -o /opt/xray-lite/manage.sh
chmod +x /opt/xray-lite/manage.sh
ln -sf /opt/xray-lite/manage.sh /usr/local/bin/xray-lite   # 可选
```

### show

输出运行状态、协议栈、监听地址、端口、UUID、Reality 的 dest / serverNames / publicKey / shortIds、XHTTP 的 mode / path / host、sockopt、performance，以及两份客户端配置的端口是否与服务端一致。私钥只显示头尾。运行状态：有 systemd unit 就看 `systemctl is-active`，否则读手动模式的 pidfile。

### set-port

只改 `config.json` 第一个入站的 `port`，其余字段不动：

1. 备份为 `config.json.bak.<时间戳>`，写入后回读校验，失败自动还原
2. 同步 `client-config.json`（只改 vnext 端口，本地 socks 1080 不动）
3. 同步 `clash-verge.yaml`（只改节点端口，`mixed-port` / DNS 不动）
4. 放行新端口（ufw / firewalld，需 root）
5. 重启服务（systemd 或 `run.sh`），检查新端口是否在监听

旧端口的防火墙规则不会自动删除。云厂商安全组不在脚本处理范围内。

### set-domain

只改这三处：

| 位置 | 改动 |
| :--- | :--- |
| `config.json` | `realitySettings.dest` → `域名:端口`（不写端口则沿用原值） |
| `config.json` | `realitySettings.serverNames` → `["域名", "*.域名"]`（IP 则只写一条） |
| 客户端配置 | `serverName` / `servername` 同步为新域名 |

如果 `xhttpSettings.host` 原本填了具体域名，会一起改成新域名；留空表示任意域名，不动。改完默认重启，`--no-restart` 跳过。目标站怎么选见 [Configuration](./Configuration.md#reality-伪装域名怎么选)。

### export

默认导出到 `~/xray-lite-export-<时间戳>/`：

| 文件 | 说明 |
| :--- | :--- |
| `config.json` | 服务端配置，权限设为 `600` |
| `client-config.json` | Xray 系客户端 |
| `clash-verge.yaml` | mihomo / Clash Verge Rev |
| `vless-link.txt` | 拼好的 `vless://` 链接，可直接导入或扫码 |

跑完会打印 `scp` 命令。导出内容含私钥和 UUID，别提交到公开仓库。

### rebuild

```bash
xray-lite rebuild           # 交互确认后重建
xray-lite rebuild --yes     # 跳过确认（脚本化）
```

等价于「卸载干净再重新安装」，会重新生成 UUID、Reality 密钥、shortId 和两份客户端配置。和直接重跑 `install.sh` 的区别是它**先把上一轮的残留清干净**。

| 步骤 | 做什么 |
| :--- | :--- |
| 0 | 检查 root、确认意图、确认能拿到 `install.sh`（拿不到就直接退出，不动任何东西） |
| 1 | 备份 `config.json` / 两份客户端配置到 `~/xray-lite-backup-<时间戳>/` |
| 2 | 停服务：`systemctl stop`（并 `disable`）、`run.sh stop`、按 pidfile 结束、按路径 `pkill`；10 秒不退则 `kill -9` |
| 3 | 清残留：systemd unit、journald 轮转配置、`run.sh`、pid、日志、旧配置、`*.bak.*`、`*.new` 临时文件、快捷命令 |
| 4 | 调用 `install.sh` 重新安装（重新询问端口和域名，重新下载二进制） |

几个设计取舍：

- **只杀本安装目录下的 `vless-server`**，不会误伤机器上别的同名进程。
- **保留 `manage.sh` 自己**。安装脚本下载新版时先写 `manage.sh.new` 再 `mv`，`mv` 是原子替换，正在执行的脚本不会被截断。
- **拿不到安装脚本就不开工**：优先用 `/opt/xray-lite/install.sh`（安装时留下的副本，离线可用），没有才联网下载；`--installer PATH` 可指定自建源或离线包。
- 安装失败时返回非零退出码，并打印用备份恢复的命令。

重建完成后会自动跑一次 `show`，并提示用 `export` 导出新配置。

## run.sh

由 `install.sh` 在手动模式下生成，路径 `/opt/xray-lite/run.sh`，POSIX sh 实现，busybox 环境可用。systemd 模式下**不会生成**。

| 命令 | 作用 |
| :--- | :--- |
| `start` | 后台启动（启动前检查日志大小，超过 10MB 轮转为 `.log.1`） |
| `stop` | 停止（TERM，等 5 秒，不退则 KILL） |
| `restart` | 停止后启动 |
| `status` | 按 pidfile 判断是否在运行 |
| `log` | `tail -f` 日志 |

`start` 实际是启动一个 `_supervise` 子进程：它拉起 `vless-server` 并 `wait`，子进程退出后 3 秒重启；如果启动后 3 秒内就退出（通常是配置或端口问题），不再重启，直接退出。pidfile 记录的是守护进程。

日志为 `/opt/xray-lite/xray-lite.log`，单文件上限 10MB，下次启动时轮转。

**不要 `kill` vless-server 子进程**，守护会在 3 秒后把它拉起来。停服务用 `run.sh stop`。

## uninstall.sh

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)
```

要求 root。默认先备份 `config.json`、`client-config.json`、`clash-verge.yaml` 到 `~/xray-lite-backup-<时间戳>/`。

| 参数 | 作用 |
| :--- | :--- |
| `--purge` | 不备份，直接删除 |
| `--remove-firewall` | 一并删除安装时添加的 ufw / firewalld 端口规则 |

步骤：停服务并 `disable` → 备份配置 → 删除安装目录、unit、快捷命令 → 删除 journald 轮转配置 → （可选）删除防火墙规则。历史日志留在 journal 中自然过期。

## vless-server

直接运行时可用：

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `-c`, `--config` | `config.json` | 配置文件路径 |
| `-l`, `--log-level` | `info` | `trace` / `debug` / `info` / `warn` / `error` |
| `RUST_LOG` | — | 环境变量，优先级高于 `--log-level` |

XDP 版额外参数见 [XDP Features](./XDP_Features.md) 和 [Configuration](./Configuration.md#xdp-environment-variables)。

返回 [README](../README.md) | 文档索引 [Home](./Home.md)。
