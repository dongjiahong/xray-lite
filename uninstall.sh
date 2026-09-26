#!/bin/bash

# Xray-Lite Uninstall Script
# Xray-Lite 卸载脚本
#
# Usage / 用法:
#   bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)
#
# Or / 或者:
#   sudo bash uninstall.sh
#
# Options / 选项:
#   --purge             不备份配置，直接删除 / Do not back up configs, delete everything
#   --remove-firewall   同时删除安装时添加的防火墙端口规则 / Also remove the firewall port rule
#
# 默认行为：先把 config.json 和两份客户端配置备份到 ~/xray-lite-backup-<时间戳>，再删除安装。
# Default: back up config.json and both client configs to ~/xray-lite-backup-<timestamp>, then remove.

set -e

# Color definitions / 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths, kept in sync with install.sh / 路径，与 install.sh 保持一致
INSTALL_DIR="/opt/xray-lite"
SERVICE_NAME="xray-lite"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
JOURNALD_DIR="/etc/systemd/journald.conf.d"
JOURNALD_CONF="${JOURNALD_DIR}/${SERVICE_NAME}.conf"

PURGE="n"
REMOVE_FIREWALL="n"

for arg in "$@"; do
    case "$arg" in
        --purge)
            PURGE="y"
            ;;
        --remove-firewall)
            REMOVE_FIREWALL="y"
            ;;
        -h|--help)
            echo "Usage / 用法: bash uninstall.sh [--purge] [--remove-firewall]"
            echo "  --purge             不备份配置 / Do not back up configs"
            echo "  --remove-firewall   同时删除防火墙端口规则 / Also remove the firewall port rule"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option / 未知选项: $arg${NC}"
            exit 1
            ;;
    esac
done

# Check if running as root / 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root / 请使用 root 权限运行${NC}"
    echo "sudo bash uninstall.sh"
    exit 1
fi

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Xray-Lite Uninstall / Xray-Lite 卸载${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Nothing installed? / 是否装过
if [ ! -d "$INSTALL_DIR" ] && [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${YELLOW}未发现 Xray-Lite 安装（$INSTALL_DIR 与服务文件都不存在）/ No installation found${NC}"
    exit 0
fi

# Read the listen port before config.json is gone / 删除前先取出监听端口
PORT=""
if [ -f "$INSTALL_DIR/config.json" ]; then
    PORT=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$INSTALL_DIR/config.json" | head -n 1 | grep -o '[0-9]*') || true
fi

# Backup path / 备份路径
BACKUP_DIR=""
BACKED_UP="n"
if [ "$PURGE" = "n" ]; then
    BACKUP_DIR="${HOME:-/root}/xray-lite-backup-$(date +%Y%m%d-%H%M%S)"
fi

echo -e "${YELLOW}将要执行 / Will do:${NC}"
echo "  - 停止并禁用服务 stop & disable service: $SERVICE_NAME"
echo "  - 删除安装目录 remove install dir: $INSTALL_DIR"
echo "  - 删除服务文件 remove unit file: $SERVICE_FILE"
echo "  - 删除日志轮转配置 remove journald conf: $JOURNALD_CONF"
if [ -n "$BACKUP_DIR" ]; then
    echo -e "  - ${GREEN}备份配置到 / back up configs to: $BACKUP_DIR${NC}"
else
    echo -e "  - ${RED}--purge: 不备份，配置将永久丢失 / no backup, configs are gone${NC}"
fi
if [ "$REMOVE_FIREWALL" = "y" ]; then
    if [ -n "$PORT" ]; then
        echo "  - 删除防火墙规则 remove firewall rule: $PORT/tcp"
    else
        echo -e "  - ${YELLOW}--remove-firewall: 未从 config.json 读到端口，跳过 / no port found, skipped${NC}"
    fi
fi
echo ""

# piped through `curl | bash` leaves stdin non-interactive, same as install.sh
if [ -t 0 ]; then
    # read 在 EOF 时返回非零，set -e 会直接终止脚本；这里统一按“取消”处理
    read -p "确认卸载？/ Confirm uninstall? (y/N): " CONFIRM || CONFIRM="n"
    case "$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')" in
        y|yes) ;;
        *)
            echo "已取消 / Cancelled"
            exit 0
            ;;
    esac
else
    echo -e "${YELLOW}非交互模式，直接执行 / Non-interactive mode, proceeding${NC}"
fi
echo ""

# 1. Stop service / 停止服务
echo -e "${YELLOW}[1/5] Stopping service... / 停止服务...${NC}"
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
fi
# Only kill processes started from this install dir / 只杀本安装目录下的进程
pkill -f "$INSTALL_DIR/vless-server" || true
echo -e "${GREEN}✓ Service stopped / 服务已停止${NC}"
echo ""

# 2. Backup configuration / 备份配置
echo -e "${YELLOW}[2/5] Backing up configuration... / 备份配置...${NC}"
if [ -n "$BACKUP_DIR" ]; then
    for f in config.json client-config.json clash-verge.yaml; do
        if [ -f "$INSTALL_DIR/$f" ]; then
            mkdir -p "$BACKUP_DIR"
            cp -p "$INSTALL_DIR/$f" "$BACKUP_DIR/"
            BACKED_UP="y"
            echo -e "${GREEN}✓ $f${NC}"
        fi
    done
    if [ "$BACKED_UP" = "y" ]; then
        echo -e "${GREEN}✓ 备份完成 / Backup saved: $BACKUP_DIR${NC}"
    else
        echo -e "${YELLOW}⚠ 安装目录里没有可备份的配置文件 / Nothing to back up${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 跳过备份 (--purge) / Backup skipped${NC}"
fi
echo ""

# 3. Remove files / 删除文件
echo -e "${YELLOW}[3/5] Removing files... / 删除文件...${NC}"
rm -rf "$INSTALL_DIR"
rm -f "$SERVICE_FILE"
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
fi
echo -e "${GREEN}✓ 安装目录与服务文件已删除 / Install dir and unit file removed${NC}"
echo ""

# 4. Remove journald log rotation config / 删除 journald 日志轮转配置
echo -e "${YELLOW}[4/5] Removing log rotation config... / 删除日志轮转配置...${NC}"
if [ -f "$JOURNALD_CONF" ]; then
    rm -f "$JOURNALD_CONF"
    # Only removes the dir when it holds nothing else / 目录非空时保留
    rmdir "$JOURNALD_DIR" 2>/dev/null || true
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart systemd-journald >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}✓ journald 配置已删除 / journald conf removed${NC}"
else
    echo -e "${YELLOW}⚠ 未找到 $JOURNALD_CONF，跳过 / not found, skipped${NC}"
fi
echo ""

# 5. Firewall / 防火墙
echo -e "${YELLOW}[5/5] Firewall... / 防火墙...${NC}"
if [ "$REMOVE_FIREWALL" != "y" ]; then
    if [ -n "$PORT" ]; then
        echo -e "${YELLOW}⚠ 保留了端口 $PORT/tcp 的放行规则，如需删除: bash uninstall.sh --remove-firewall${NC}"
    fi
elif [ -n "$PORT" ]; then
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw delete allow "$PORT/tcp" >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ 已删除 ufw 规则 / ufw rule removed: $PORT/tcp${NC}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --remove-port="${PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ 已删除 firewalld 规则 / firewalld rule removed: $PORT/tcp${NC}"
    else
        echo -e "${YELLOW}⚠ 未检测到 ufw / firewalld，请手动删除端口 $PORT 的放行规则${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 未从 config.json 读到端口，跳过防火墙清理 / No port found, skipped${NC}"
fi
echo ""

# Summary / 结果
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  卸载完成 / Uninstall Complete${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
if [ "$BACKED_UP" = "y" ]; then
    echo -e "${BLUE}配置备份 / Config backup:${NC} $BACKUP_DIR"
    echo "  含 config.json（私钥 / UUID）、client-config.json、clash-verge.yaml"
    echo ""
fi
echo -e "${BLUE}说明 / Notes:${NC}"
echo "  - 历史日志仍留在 journal 中，会随系统日志轮转自然过期；如需立刻清理："
echo "    journalctl --rotate && journalctl --vacuum-time=1s   # 注意：影响所有服务的日志"
echo "  - 重新安装 / Reinstall:"
echo "    bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh)"
echo ""
