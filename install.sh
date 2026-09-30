#!/bin/bash

# Xray-Lite One-Click Installation Script
# Xray-Lite 一键安装脚本
# 
# Usage / 用法:
#   curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh | bash
#
# Or / 或者:
#   wget -qO- https://raw.githubusercontent.com/dongjiahong/xray-lite/main/install.sh | bash
#
# Options / 选项:
#   --systemd   安装为 systemd 服务 / install as a systemd service
#   --manual    手动运行模式（生成 run.sh）/ manual run mode
#   不带参数时交互选择；无 systemd 的系统（如 Alpine）自动用手动运行模式
#   Without arguments the mode is chosen interactively; systems without systemd fall back to manual mode
#
#   bash <(curl -fsSL .../install.sh) --manual
#   XRAY_LITE_DEPLOY=manual curl -fsSL .../install.sh | bash

set -e

# Color definitions / 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Version / 版本
VERSION="v0.4.7"
REPO="dongjiahong/xray-lite"

# Installation directory / 安装目录
INSTALL_DIR="/opt/xray-lite"

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  Xray-Lite One-Click Installation${NC}"
echo -e "${BLUE}  Xray-Lite 一键安装${NC}"
echo -e "${BLUE}  Version / 版本: ${VERSION}${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check if running as root / 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root / 请使用 root 权限运行${NC}"
    echo "sudo bash install.sh"
    exit 1
fi

# Detect architecture / 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        BINARY_ARCH="x86_64"
        ;;
    aarch64|arm64)
        BINARY_ARCH="aarch64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH / 不支持的架构: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Detected architecture / 检测到架构: $ARCH${NC}"
echo ""

if [ "$BINARY_ARCH" = "amd64" ] || [ "$BINARY_ARCH" = "x86_64" ]; then
    XRAY_BINARY_NAME="xray-linux-amd64"
else
    # Fallback for arm64
    XRAY_BINARY_NAME="vless-server-linux-aarch64"
fi
echo ""

# Deployment mode: options and detection / 部署方式：参数与环境检测
# 必须在停止旧服务之前确定，否则不知道要不要碰 systemd
DEPLOY_MODE="${XRAY_LITE_DEPLOY:-}"

for arg in "$@"; do
    case "$arg" in
        --systemd) DEPLOY_MODE="systemd" ;;
        --manual)  DEPLOY_MODE="manual" ;;
        -h|--help)
            echo "Usage / 用法: bash install.sh [--systemd|--manual]"
            echo "  --systemd   安装为 systemd 服务 / install as a systemd service"
            echo "  --manual    手动运行模式 / manual run mode (run.sh + nohup)"
            echo "  也可用环境变量 / or env: XRAY_LITE_DEPLOY=systemd|manual"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option / 未知选项: $arg${NC}"
            exit 1
            ;;
    esac
done

case "$DEPLOY_MODE" in
    ""|systemd|manual) ;;
    *)
        echo -e "${RED}XRAY_LITE_DEPLOY must be systemd or manual / 只能为 systemd 或 manual${NC}"
        exit 1
        ;;
esac

SYSTEMD_AVAILABLE="n"
if command -v systemctl >/dev/null 2>&1; then
    SYSTEMD_AVAILABLE="y"
fi

# 明确要了 systemd 但系统没有，只能用手动模式
if [ "$DEPLOY_MODE" = "systemd" ] && [ "$SYSTEMD_AVAILABLE" != "y" ]; then
    echo -e "${RED}systemctl not found, falling back to manual mode / 未找到 systemctl，改用手动运行模式${NC}"
    DEPLOY_MODE="manual"
fi

# 停掉上一次安装留下的进程 / stop leftovers from a previous install
# Alpine 等精简系统上 pkill / killall 未必存在，能试的都试一遍
stop_existing_process() {
    local pid
    if [ -f "$INSTALL_DIR/xray-lite.pid" ]; then
        pid=$(cat "$INSTALL_DIR/xray-lite.pid" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$INSTALL_DIR/xray-lite.pid"
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "vless-server" 2>/dev/null || true
    fi
    if command -v killall >/dev/null 2>&1; then
        killall vless-server 2>/dev/null || true
    fi
}

# Stop existing service / 停止现有服务
echo -e "${YELLOW}Checking for existing installation... / 检查现有安装...${NC}"
if [ "$SYSTEMD_AVAILABLE" = "y" ] && systemctl is-active --quiet xray-lite; then
    echo "Stopping existing xray-lite service... / 停止现有 xray-lite 服务..."
    systemctl stop xray-lite >/dev/null 2>&1
    systemctl disable xray-lite >/dev/null 2>&1
fi

# Kill any lingering vless-server processes (covers manual mode)
stop_existing_process

echo ""

# Create installation directory / 创建安装目录
echo -e "${YELLOW}[1/6] Creating installation directory... / 创建安装目录...${NC}"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR
echo -e "${GREEN}✓ Directory created / 目录已创建: $INSTALL_DIR${NC}"
echo ""

# Deployment mode: ask when not specified / 未指定时交互选择部署方式
if [ -z "$DEPLOY_MODE" ]; then
    if [ "$SYSTEMD_AVAILABLE" = "y" ] && [ -t 0 ]; then
        echo -e "${YELLOW}Deployment / 部署方式:${NC}"
        echo "  1) systemd service (默认 default) — 开机自启，日志走 journalctl"
        echo "  2) manual run — 手动运行，用 $INSTALL_DIR/run.sh 管理，日志写文件"
        read -p "Choice / 选择 [1]: " MODE_INPUT
        case "${MODE_INPUT:-1}" in
            2|m|manual) DEPLOY_MODE="manual" ;;
            *) DEPLOY_MODE="systemd" ;;
        esac
    elif [ "$SYSTEMD_AVAILABLE" = "y" ]; then
        DEPLOY_MODE="systemd"
    else
        DEPLOY_MODE="manual"
        echo -e "${YELLOW}未检测到 systemd，使用手动运行模式 / No systemd found, using manual mode${NC}"
    fi
fi

if [ "$DEPLOY_MODE" = "systemd" ]; then
    echo -e "${GREEN}✓ Deployment / 部署方式: systemd service${NC}"
else
    echo -e "${GREEN}✓ Deployment / 部署方式: manual run (run.sh + nohup)${NC}"
fi
echo ""

# Download binary / 下载二进制文件
# Download Static Binaries / 下载静态二进制文件
echo -e "${YELLOW}[2/6] Downloading Xray-Lite binaries... / 下载 Xray-Lite 二进制文件...${NC}"

XRAY_BINARY="${XRAY_BINARY_NAME}"

if [ "$BINARY_ARCH" = "amd64" ] || [ "$BINARY_ARCH" = "x86_64" ]; then
    KEYGEN_BINARY="keygen-linux-x86_64"
else
    KEYGEN_BINARY="keygen-linux-${BINARY_ARCH}"
fi

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${VERSION}"
FALLBACK_PREFIX="https://github.com/${REPO}/releases/download/${VERSION}"

echo "Downloading vless-server..."
if curl -fsSL "${DOWNLOAD_PREFIX}/${XRAY_BINARY}" -o "vless-server"; then
    echo -e "${GREEN}✓ vless-server downloaded${NC}"
else
    echo -e "${RED}Failed to download vless-server${NC}"
    exit 1
fi

echo "Downloading keygen..."
if curl -fsSL "${DOWNLOAD_PREFIX}/${KEYGEN_BINARY}" -o "keygen"; then
    echo -e "${GREEN}✓ keygen downloaded${NC}"
else
    echo -e "${RED}Failed to download keygen${NC}"
    exit 1
fi

chmod +x vless-server keygen
echo -e "${GREEN}✓ Files prepared / 文件已准备就绪${NC}"
echo ""

# Generate configuration / 生成配置
echo -e "${YELLOW}[4/6] Generating configuration... / 生成配置...${NC}"

# Generate keys / 生成密钥
KEYGEN_OUTPUT=$(./keygen)
PRIVATE_KEY=$(echo "$KEYGEN_OUTPUT" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYGEN_OUTPUT" | grep "Public key:" | awk '{print $3}')

# Generate UUID / 生成 UUID
CLIENT_UUID=$(cat /proc/sys/kernel/random/uuid)

# Get server IP / 获取服务器 IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")

# Interactive configuration / 交互式配置
echo ""
if [ -t 0 ]; then
    read -p "Server port / 服务器端口 [443]: " PORT_INPUT
    PORT=${PORT_INPUT:-443}
else
    PORT=443
    echo "Non-interactive mode detected using default port 443 / 检测到非交互模式，使用默认端口 443"
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${YELLOW}Invalid port, using default 443 / 端口无效，使用默认 443${NC}"
    PORT=443
fi

if [ -t 0 ]; then
    read -p "Masquerade website / 伪装网站 [www.microsoft.com:443]: " DEST_INPUT
    DEST=${DEST_INPUT:-www.microsoft.com:443}
else
    DEST="www.microsoft.com:443"
fi

DOMAIN=$(echo $DEST | cut -d: -f1)

# Short ID configuration
if command -v openssl &> /dev/null; then
    SHORT_ID=$(openssl rand -hex 8)
else
    SHORT_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 16)
fi

# XHTTP configuration / XHTTP 配置
ENABLE_XHTTP="n"
NETWORK_TYPE="tcp"
XHTTP_MODE="auto"
XHTTP_PATH="/"

if [ -t 0 ]; then
    echo ""
    echo -e "${YELLOW}XHTTP provides additional obfuscation via HTTP/2${NC}"
    echo -e "${YELLOW}XHTTP 通过 HTTP/2 提供额外的混淆${NC}"
    read -p "Enable XHTTP? / 启用 XHTTP? (y/N): " XHTTP_INPUT
    ENABLE_XHTTP=$(echo "${XHTTP_INPUT:-n}" | tr '[:upper:]' '[:lower:]')
    
    if [ "$ENABLE_XHTTP" = "y" ]; then
        NETWORK_TYPE="http"
        XHTTP_MODE="auto"
        
        echo ""
        read -p "XHTTP path / XHTTP 路径 [/]: " PATH_INPUT
        XHTTP_PATH=${PATH_INPUT:-/}
        # Auto-prepend / if missing
        if [[ "$XHTTP_PATH" != /* ]]; then
            XHTTP_PATH="/$XHTTP_PATH"
        fi
        
        read -p "XHTTP host / XHTTP 域名 (Optional/可选) []: " HOST_INPUT
        XHTTP_HOST=${HOST_INPUT}

        echo -e "${GREEN}✓ XHTTP enabled / XHTTP 已启用${NC}"
        echo "  Mode: Intelligent Adaptive (Integrated) / 智能自适应"
        echo "  Path / 路径: $XHTTP_PATH"
        echo "  Host / 域名: ${XHTTP_HOST:-*(Any)}"
    else
        echo -e "${GREEN}✓ Using TCP (default) / 使用 TCP (默认)${NC}"
    fi
fi

# Create server configuration with conditional XHTTP
# Build XHTTP settings if enabled
if [ "$ENABLE_XHTTP" = "y" ]; then
    XHTTP_SETTINGS=",
        \"xhttpSettings\": {
          \"mode\": \"$XHTTP_MODE\",
          \"path\": \"$XHTTP_PATH\",
          \"host\": \"$XHTTP_HOST\"
        }"
else
    XHTTP_SETTINGS=""
fi

cat > config.json << EOF
{
  "log": {
    "loglevel": "info"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$CLIENT_UUID",
            "flow": "",
            "email": "user@example.com"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "$NETWORK_TYPE",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST",
          "xver": 0,
          "serverNames": [
            "$DOMAIN",
            "*.$DOMAIN"
          ],
          "privateKey": "$PRIVATE_KEY",
          "publicKey": "$PUBLIC_KEY",
          "shortIds": ["$SHORT_ID"],
          "fingerprint": "chrome"
        }$XHTTP_SETTINGS
      }
    }
  ],
  "outbounds": [{
    "protocol": "freedom",
    "tag": "direct"
  }],
  "routing": {
    "rules": []
  }
}
EOF

# Client transport settings / 客户端传输设置
# 服务端用 XHTTP 时客户端必须走 xhttp，否则会按裸 TCP 解析而连不上
if [ "$ENABLE_XHTTP" = "y" ]; then
    CLIENT_STREAM_SETTINGS="\"network\": \"xhttp\",
      \"security\": \"reality\",
      \"realitySettings\": {
        \"show\": false,
        \"fingerprint\": \"chrome\",
        \"serverName\": \"$DOMAIN\",
        \"publicKey\": \"$PUBLIC_KEY\",
        \"shortId\": \"$SHORT_ID\"
      },
      \"xhttpSettings\": {
        \"mode\": \"$XHTTP_MODE\",
        \"path\": \"$XHTTP_PATH\",
        \"host\": \"$XHTTP_HOST\"
      }"
else
    CLIENT_STREAM_SETTINGS="\"network\": \"tcp\",
      \"security\": \"reality\",
      \"realitySettings\": {
        \"show\": false,
        \"fingerprint\": \"chrome\",
        \"serverName\": \"$DOMAIN\",
        \"publicKey\": \"$PUBLIC_KEY\",
        \"shortId\": \"$SHORT_ID\",
        \"spiderX\": \"/\"
      }"
fi

# Create client configuration (Xray JSON) / 生成客户端配置 (Xray)
cat > client-config.json << EOF
{
  "log": {"loglevel": "info"},
  "inbounds": [{
    "port": 1080,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {"udp": true}
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$SERVER_IP",
        "port": $PORT,
        "users": [{
          "id": "$CLIENT_UUID",
          "encryption": "none",
          "flow": ""
        }]
      }]
    },
    "streamSettings": {
      $CLIENT_STREAM_SETTINGS
    }
  }]
}
EOF

# mihomo / Clash Verge Rev proxy entry / mihomo 客户端节点
if [ "$ENABLE_XHTTP" = "y" ]; then
    MIHOMO_PROXY="  - name: \"xray-lite\"
    type: vless
    server: $SERVER_IP
    port: $PORT
    uuid: $CLIENT_UUID
    udp: true
    tls: true
    servername: $DOMAIN
    client-fingerprint: chrome
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
    # xhttp 传输，需要 mihomo 内核 >= v1.19.22
    # mode: auto 在 Reality 下等价于 stream-one。若服务端是 v0.4.6 及更早版本，
    # 请把 mode 改成 stream-up，否则每条连接会多等 2 秒。
    network: xhttp
    alpn: [h2]
    xhttp-opts:
      path: \"$XHTTP_PATH\"
      mode: auto"
else
    MIHOMO_PROXY="  - name: \"xray-lite\"
    type: vless
    server: $SERVER_IP
    port: $PORT
    uuid: $CLIENT_UUID
    udp: true
    tls: true
    servername: $DOMAIN
    client-fingerprint: chrome
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
    network: tcp"
fi

# Create mihomo configuration / 生成 mihomo 客户端配置
cat > clash-verge.yaml << EOF
# Xray-Lite 客户端配置 — Clash Verge Rev / mihomo
# 由 install.sh 生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 直接把本文件导入 Clash Verge Rev（配置文件 -> 新建/导入本地文件）即可使用
# 注意：mihomo 没有 spider-x 字段，那是 Xray 的概念，写进来会被忽略

mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 0.0.0.0:5335
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 8.8.8.8
    - 1.1.1.1

proxies:
$MIHOMO_PROXY

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "xray-lite"
      - DIRECT

rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF

# Set permissions
echo -e "${YELLOW}Setting permissions... / 设置权限...${NC}"
chown -R nobody:nogroup $INSTALL_DIR
chmod 755 $INSTALL_DIR
chmod 644 $INSTALL_DIR/config.json
chmod 755 $INSTALL_DIR/vless-server

# Install service / 安装服务
if [ "$DEPLOY_MODE" = "systemd" ]; then
    echo -e "${YELLOW}[5/6] Installing systemd service... / 安装 systemd 服务...${NC}"

    cat > /etc/systemd/system/xray-lite.service << EOF
[Unit]
Description=Xray-Lite VLESS Reality Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
Environment=RUST_LOG=info
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/vless-server --config $INSTALL_DIR/config.json
Restart=on-failure
RestartSec=10s

LimitNOFILE=1000000
LimitNPROC=512

SyslogIdentifier=xray-lite
# tracing 默认写 stdout，必须收进 journal，否则 journalctl 看不到任何日志
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray-lite >/dev/null 2>&1
    echo -e "${GREEN}✓ Service installed / 服务已安装${NC}"
    echo ""

    # Configure journald log rotation for xray-lite / 配置 journald 日志轮转
    echo -e "${YELLOW}Configuring log rotation... / 配置日志轮转...${NC}"
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/xray-lite.conf << EOF
# Xray-Lite journald log rotation configuration
# Xray-Lite journald 日志轮转配置
[Journal]
# Maximum disk usage for logs / 日志最大磁盘使用量
SystemMaxUse=50M
# Maximum size of individual log files / 单个日志文件最大大小
SystemMaxFileSize=10M
# Log retention time (7 days) / 日志保留时间（7天）
MaxRetentionSec=7day
# Compress logs older than 1 day / 压缩超过1天的日志
Compress=yes
EOF

    # Restart journald to apply configuration / 重启 journald 应用配置
    systemctl restart systemd-journald >/dev/null 2>&1
    echo -e "${GREEN}✓ Log rotation configured (max 50MB, 7 days) / 日志轮转已配置 (最大 50MB, 7天)${NC}"
    echo ""
else
    echo -e "${YELLOW}[5/6] Setting up manual run script... / 配置手动运行脚本...${NC}"

    cat > "$INSTALL_DIR/run.sh" << 'EOF'
#!/bin/sh
# Xray-Lite manual run script / Xray-Lite 手动运行脚本
# 无 systemd 的系统（如 Alpine）用它管理进程 / manages the process on systems without systemd
# Usage: ./run.sh {start|stop|restart|status|log}

DIR="/opt/xray-lite"
BIN="$DIR/vless-server"
CONF="$DIR/config.json"
PIDFILE="$DIR/xray-lite.pid"
LOGFILE="$DIR/xray-lite.log"
# 单文件日志上限 10MB，超过则在下次启动时轮转为 xray-lite.log.1
MAXLOG=10485760

is_running() {
    [ -f "$PIDFILE" ] || return 1
    PID=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$PID" ] || return 1
    kill -0 "$PID" 2>/dev/null
}

case "$1" in
    start)
        if is_running; then
            echo "已在运行 / already running (pid $PID)"
            exit 0
        fi
        if [ -f "$LOGFILE" ] && [ "$(wc -c < "$LOGFILE")" -gt "$MAXLOG" ]; then
            mv "$LOGFILE" "$LOGFILE.1"
        fi
        cd "$DIR" || exit 1
        RUST_LOG=info nohup "$BIN" --config "$CONF" >> "$LOGFILE" 2>&1 &
        echo $! > "$PIDFILE"
        sleep 1
        if is_running; then
            echo "已启动 / started (pid $(cat "$PIDFILE"))"
        else
            echo "启动失败 / failed to start, 日志 / log: $LOGFILE"
            tail -n 20 "$LOGFILE"
            rm -f "$PIDFILE"
            exit 1
        fi
        ;;
    stop)
        if ! is_running; then
            echo "未在运行 / not running"
            rm -f "$PIDFILE"
            exit 0
        fi
        kill "$PID" 2>/dev/null
        for _ in 1 2 3 4 5; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
        rm -f "$PIDFILE"
        echo "已停止 / stopped"
        ;;
    restart)
        "$DIR/run.sh" stop
        "$DIR/run.sh" start
        ;;
    status)
        if is_running; then
            echo "运行中 / running (pid $PID)"
        else
            echo "未运行 / stopped"
            exit 1
        fi
        ;;
    log)
        tail -f "$LOGFILE"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|log}"
        exit 1
        ;;
esac
EOF

    chmod 755 "$INSTALL_DIR/run.sh"
    echo -e "${GREEN}✓ Manual run script installed / 手动运行脚本已安装: $INSTALL_DIR/run.sh${NC}"
    echo -e "${GREEN}✓ Log file / 日志文件: $INSTALL_DIR/xray-lite.log (超 10MB 下次启动时轮转)${NC}"
    echo ""
fi

# Configure firewall
echo -e "${YELLOW}[6/6] Configuring firewall... / 配置防火墙...${NC}"
# Ensure PORT is numeric again just in case
if [[ ! "$PORT" =~ ^[0-9]+$ ]]; then
    PORT=443
fi

if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        ufw allow $PORT/tcp
        echo -e "${GREEN}✓ Firewall configured (ufw) / 防火墙已配置 (ufw)${NC}"
    else
        echo -e "${YELLOW}⚠ ufw is installed but not active / ufw 已安装但未启用${NC}"
    fi
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=${PORT}/tcp >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
    echo -e "${GREEN}✓ Firewall configured (firewalld) / 防火墙已配置 (firewalld)${NC}"
else
    echo -e "${YELLOW}⚠ No firewall detected, please open port $PORT manually${NC}"
    echo -e "${YELLOW}⚠ 未检测到防火墙，请手动开放端口 $PORT${NC}"
fi
echo ""

# Check port availability / 检查端口占用
# 只看 LISTEN：lsof -i 会把 TIME_WAIT / ESTABLISHED 的旧连接也算成占用，会误判
# busybox 环境（Alpine）可能既没有 ss 也没有 lsof，用 netstat 兜底
port_holder() {
    if command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | grep -E "[:.]$1[[:space:]]" || true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltnp 2>/dev/null | grep -E "[:.]$1[[:space:]]" ||
        netstat -ltn 2>/dev/null | grep -E "[:.]$1[[:space:]]" || true
    elif command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
    fi
}

port_in_use() {
    [ -n "$(port_holder "$1")" ]
}

if port_in_use "$PORT"; then
    echo "Port $PORT is in use, attempting to clean up... / 端口 $PORT 被占用，尝试清理..."
    if [ "$SYSTEMD_AVAILABLE" = "y" ]; then
        systemctl stop xray-lite >/dev/null 2>&1 || true
    fi
    stop_existing_process
    # 旧进程退出后端口才释放，等一会儿再判断 / give the old process time to release the port
    for _ in 1 2 3 4 5; do
        port_in_use "$PORT" || break
        sleep 1
    done
fi

if port_in_use "$PORT"; then
    echo -e "${RED}Error: Port $PORT is already in use! / 错误: 端口 $PORT 已被占用!${NC}"
    echo -e "${YELLOW}占用者 / held by:${NC}"
    port_holder "$PORT"
    echo ""
    echo -e "${YELLOW}处理办法 / what to do:${NC}"
    echo "  1. 停掉上面的进程；Alpine 上没有 pkill 时 / if pkill is missing on Alpine:"
    echo "     kill \$(pidof vless-server)      # 或 apk add procps 后用 pkill -f vless-server"
    echo "  2. 或者换一个端口重新运行安装脚本 / or reinstall with another port"
    exit 1
fi

# Start service
echo -e "${YELLOW}Starting Xray-Lite... / 启动 Xray-Lite...${NC}"

if [ "$DEPLOY_MODE" = "systemd" ]; then
    systemctl start xray-lite
    sleep 2

    if systemctl is-active --quiet xray-lite; then
        echo -e "${GREEN}✓ Service started successfully / 服务启动成功${NC}"
    else
        echo -e "${RED}✗ Service failed to start / 服务启动失败${NC}"
        echo -e "${YELLOW}=== Error Logs / 错误日志 ===${NC}"
        journalctl -u xray-lite -n 20 --no-pager
        echo -e "${YELLOW}=============================${NC}"
        exit 1
    fi
else
    if "$INSTALL_DIR/run.sh" start; then
        echo -e "${GREEN}✓ Started successfully / 启动成功${NC}"
    else
        echo -e "${RED}✗ Failed to start / 启动失败${NC}"
        exit 1
    fi
fi
echo ""

# Display summary
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Installation Complete! / 安装完成！${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${BLUE}Server Information / 服务器信息:${NC}"
echo "  IP: $SERVER_IP"
echo "  Port / 端口: $PORT"
echo "  UUID: $CLIENT_UUID"
echo "  Public Key / 公钥: $PUBLIC_KEY"
echo "  Short ID / 短 ID: $SHORT_ID"
echo ""
echo -e "${BLUE}Client Configuration / 客户端配置:${NC}"
echo "  Clash Verge Rev / mihomo (推荐): $INSTALL_DIR/clash-verge.yaml"
echo "  Xray 客户端:                     $INSTALL_DIR/client-config.json"
echo "  Download / 下载: scp root@$SERVER_IP:$INSTALL_DIR/clash-verge.yaml ."
echo ""
echo -e "${BLUE}Service Management / 服务管理:${NC}"
if [ "$DEPLOY_MODE" = "systemd" ]; then
    echo "  Start / 启动:   systemctl start xray-lite"
    echo "  Stop / 停止:    systemctl stop xray-lite"
    echo "  Restart / 重启: systemctl restart xray-lite"
    echo "  Status / 状态:  systemctl status xray-lite"
    echo "  Logs / 日志:    journalctl -u xray-lite -f"
else
    echo "  Start / 启动:   $INSTALL_DIR/run.sh start"
    echo "  Stop / 停止:    $INSTALL_DIR/run.sh stop"
    echo "  Restart / 重启: $INSTALL_DIR/run.sh restart"
    echo "  Status / 状态:  $INSTALL_DIR/run.sh status"
    echo "  Logs / 日志:    $INSTALL_DIR/run.sh log   (或直接看 $INSTALL_DIR/xray-lite.log)"
    echo ""
    echo -e "${YELLOW}手动运行模式不会开机自启 / manual mode does not auto-start on boot${NC}"
    echo -e "${YELLOW}Alpine: 把 $INSTALL_DIR/run.sh start 写进 /etc/local.d/xray-lite.start，再执行 rc-update add local default${NC}"
fi
echo ""
echo -e "${BLUE}Uninstall / 卸载:${NC}"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/dongjiahong/xray-lite/main/uninstall.sh)"
echo ""
echo -e "${YELLOW}Next Steps / 下一步:${NC}"
echo "  1. Download client config / 下载客户端配置 (clash-verge.yaml)"
echo "  2. Import into Clash Verge Rev (or other client) / 导入到客户端"
echo "  3. Connect and enjoy! / 连接并享受！"
echo ""
