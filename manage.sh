#!/bin/bash

# Xray-Lite Management Tool
# Xray-Lite 管理工具
#
# 只做两件事 / two jobs only:
#   1. show      打印当前生效的配置（协议栈、端口、UUID、Reality、XHTTP、性能参数…）
#   2. set-port  只改监听端口，UUID / 私钥 / shortId / 传输方式等一律不动
#
# Usage / 用法:
#   bash manage.sh                                  # 等同 show
#   bash manage.sh show
#   bash manage.sh set-port 8443
#   bash manage.sh set-port 8443 --no-restart       # 只改文件，不重启服务
#   bash manage.sh set-port 8443 --no-clients       # 不更新客户端配置
#   bash manage.sh show -c /opt/xray-lite/config.json
#
# Options / 参数:
#   -c, --config PATH   指定 config.json（默认 /opt/xray-lite/config.json）
#       --no-restart    改完端口不重启服务
#       --no-clients    不更新同目录下的 client-config.json / clash-verge.yaml
#
# 说明：直接操作 install.sh 生成的配置文件，保持其它字段原样不动。

set -o pipefail 2>/dev/null || true

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

SERVICE_NAME="xray-lite"

die() {
    echo -e "${RED}错误 / Error: $*${NC}" >&2
    exit 1
}

ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }

usage() {
    cat << 'EOF'
Xray-Lite 管理工具 / Management Tool

用法 / Usage:
  manage.sh                          显示当前配置 (同 show)
  manage.sh show                     显示当前配置
  manage.sh set-port <端口>           只改监听端口，其它配置保持不变

参数 / Options:
  -c, --config PATH   指定 config.json（默认 /opt/xray-lite/config.json）
  --no-restart        改完端口不重启服务
  --no-clients        不更新 client-config.json / clash-verge.yaml

示例 / Examples:
  manage.sh
  manage.sh set-port 8443
  manage.sh set-port 2053 --no-restart
EOF
}

# ---------------------------------------------------------------------------
# JSON / YAML 读取（不依赖 jq；只认 install.sh 生成的扁平结构）
# ---------------------------------------------------------------------------

# 读取字符串字段：第一个匹配行里的值
json_str() {
    sed -n -E "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" | head -n 1
}

# 读取数字字段
json_num() {
    sed -n -E "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$1" | head -n 1
}

# 读取布尔字段
json_bool() {
    sed -n -E "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" "$1" | head -n 1
}

# 读取数组字段（可跨行），输出以 ", " 连接
json_arr() {
    awk -v k="\"$2\"" '
        function flush(   i, out) {
            out = ""
            for (i = 1; i <= n; i++) out = out (i > 1 ? ", " : "") v[i]
            print out
        }
        !started && index($0, k) {
            started = 1
            line = $0
            sub(".*" k "[[:space:]]*:[[:space:]]*\\[", "", line)
            closed = index(line, "]")
            if (closed) line = substr(line, 1, closed - 1)
            s = line
            while (match(s, /"[^"]*"/)) {
                v[++n] = substr(s, RSTART + 1, RLENGTH - 2)
                s = substr(s, RSTART + RLENGTH)
            }
            if (closed) { flush(); exit }
            next
        }
        started {
            closed = index($0, "]")
            s = closed ? substr($0, 1, closed - 1) : $0
            while (match(s, /"[^"]*"/)) {
                v[++n] = substr(s, RSTART + 1, RLENGTH - 2)
                s = substr(s, RSTART + RLENGTH)
            }
            if (closed) { flush(); exit }
        }
    ' "$1"
}

# 客户端配置里的 outbound 端口（vnext 之后的第一个 port）
client_json_port() {
    awk '/"vnext"[[:space:]]*:/ { v = 1 }
         v && match($0, /"port"[[:space:]]*:[[:space:]]*[0-9]+/) {
             s = substr($0, RSTART, RLENGTH)
             gsub(/[^0-9]/, "", s)
             print s
             exit
         }' "$1"
}

# mihomo 配置里 vless 节点的端口
client_yaml_port() {
    awk '/^[[:space:]]*type:[[:space:]]*vless/ { v = 1 }
         v && match($0, /port:[[:space:]]*[0-9]+/) {
             s = substr($0, RSTART, RLENGTH)
             gsub(/[^0-9]/, "", s)
             print s
             exit
         }' "$1"
}

# ---------------------------------------------------------------------------
# 配置文件修改（只动匹配到的那一行，其余字节保持不变）
# ---------------------------------------------------------------------------

# 服务端 config.json：只改 inbounds 里的第一个 port
edit_inbound_port() {
    local file=$1 new=$2 tmp rc
    tmp="${file}.tmp.$$"
    cp -p "$file" "$tmp" || return 1
    LC_ALL=C awk -v p="$new" '
        /"inbounds"[[:space:]]*:/ { inside = 1 }
        /"outbounds"[[:space:]]*:/ { inside = 0 }
        inside && !done && match($0, /"port"[[:space:]]*:[[:space:]]*[0-9]+/) {
            print substr($0, 1, RSTART - 1) "\"port\": " p substr($0, RSTART + RLENGTH)
            done = 1
            next
        }
        { print }
        END { if (!done) exit 3 }
    ' "$file" > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
    mv "$tmp" "$file"
}

# client-config.json：只改 vnext 里的 port（inbounds 的 socks 端口 1080 不动）
edit_client_json_port() {
    local file=$1 new=$2 tmp rc
    tmp="${file}.tmp.$$"
    cp -p "$file" "$tmp" || return 1
    LC_ALL=C awk -v p="$new" '
        /"vnext"[[:space:]]*:/ { v = 1 }
        v && !done && match($0, /"port"[[:space:]]*:[[:space:]]*[0-9]+/) {
            print substr($0, 1, RSTART - 1) "\"port\": " p substr($0, RSTART + RLENGTH)
            done = 1
            next
        }
        { print }
        END { if (!done) exit 3 }
    ' "$file" > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
    mv "$tmp" "$file"
}

# clash-verge.yaml：只改 vless 节点的 port（mixed-port / dns 端口不动）
edit_yaml_port() {
    local file=$1 new=$2 tmp rc
    tmp="${file}.tmp.$$"
    cp -p "$file" "$tmp" || return 1
    LC_ALL=C awk -v p="$new" '
        /^[[:space:]]*type:[[:space:]]*vless/ { v = 1 }
        v && !done && match($0, /port:[[:space:]]*[0-9]+/) {
            print substr($0, 1, RSTART - 1) "port: " p substr($0, RSTART + RLENGTH)
            done = 1
            next
        }
        { print }
        END { if (!done) exit 3 }
    ' "$file" > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
    mv "$tmp" "$file"
}

backup() {
    local file=$1 ts=$2
    cp -p "$file" "${file}.bak.${ts}" || return 1
    echo "${file}.bak.${ts}"
}

# ---------------------------------------------------------------------------
# 端口占用 / 防火墙 / 服务
# ---------------------------------------------------------------------------

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

open_firewall() {
    local port=$1
    if [ "$EUID" -ne 0 ]; then
        warn "非 root，跳过防火墙设置，请手动放行 $port/tcp"
        return 1
    fi
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            if ufw allow "$port/tcp" >/dev/null 2>&1; then
                ok "防火墙已放行 $port/tcp (ufw)"
                return 0
            fi
            warn "ufw 放行失败，请手动执行: ufw allow $port/tcp"
        else
            warn "ufw 已安装但未启用，跳过"
        fi
        return 1
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 &&
           firewall-cmd --reload >/dev/null 2>&1; then
            ok "防火墙已放行 $port/tcp (firewalld)"
            return 0
        fi
        warn "firewalld 放行失败，请手动执行: firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload"
        return 1
    fi
    warn "未检测到 ufw / firewalld，请自行确认 $port/tcp 已放行"
    return 1
}

restart_service() {
    local dir=$1
    if [ "$EUID" -ne 0 ]; then
        warn "非 root，跳过重启。请手动重启服务后再测试"
        return 2
    fi
    if command -v systemctl >/dev/null 2>&1 &&
       [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        if systemctl restart "$SERVICE_NAME"; then
            ok "服务已重启 (systemd: $SERVICE_NAME)"
            return 0
        fi
        warn "systemd 重启失败，查看日志: journalctl -u $SERVICE_NAME -n 50 --no-pager"
        return 1
    fi
    if [ -x "$dir/run.sh" ]; then
        if "$dir/run.sh" restart; then
            ok "服务已重启 (manual: $dir/run.sh)"
            return 0
        fi
        warn "重启失败，查看日志: $dir/xray-lite.log"
        return 1
    fi
    warn "未找到 systemd 服务或 run.sh，请手动启动 vless-server"
    return 1
}

# ---------------------------------------------------------------------------
# show
# ---------------------------------------------------------------------------

mask_key() {
    echo "$1" | awk '{ if (length($0) <= 12) print "****"; else print substr($0, 1, 6) "..." substr($0, length($0) - 3) }'
}

bool_cn() {
    if [ "$1" = "true" ]; then echo "on"; else echo "off"; fi
}

show_config() {
    local cfg=$1 dir listen port proto flow network security
    local stack has_xhttp ids n_ids

    dir=$(dirname "$cfg")

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Xray-Lite 当前配置 / Current Config${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "配置文件: $cfg"

    # 运行状态
    if command -v systemctl >/dev/null 2>&1 &&
       [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "运行状态: ${GREEN}运行中${NC} (systemd: $SERVICE_NAME)"
        else
            echo -e "运行状态: ${RED}未运行${NC} (systemd: $SERVICE_NAME)"
        fi
    elif [ -x "$dir/run.sh" ]; then
        local pid=""
        [ -f "$dir/xray-lite.pid" ] && pid=$(cat "$dir/xray-lite.pid" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo -e "运行状态: ${GREEN}运行中${NC} (manual, pid $pid)"
        else
            echo -e "运行状态: ${RED}未运行${NC} (manual, $dir/run.sh)"
        fi
    else
        echo "运行状态: 未检测到 systemd 服务或 run.sh"
    fi

    echo ""

    listen=$(json_str "$cfg" listen)
    [ -z "$listen" ] && listen="0.0.0.0"
    port=$(json_num "$cfg" port)
    proto=$(json_str "$cfg" protocol)
    flow=$(json_str "$cfg" flow)
    network=$(json_str "$cfg" network)
    security=$(json_str "$cfg" security)
    has_xhttp=0
    grep -q '"xhttpSettings"' "$cfg" && has_xhttp=1

    stack=$(echo "${proto:-vless}" | tr '[:lower:]' '[:upper:]')
    [ -n "$flow" ] && stack="$stack + XTLS-Vision"
    case "$security" in
        reality) stack="$stack + REALITY" ;;
        tls)     stack="$stack + TLS" ;;
    esac
    [ "$has_xhttp" = 1 ] && stack="$stack + XHTTP"

    echo -e "${BOLD}监听 / Listen:${NC} ${listen}:${port}"
    echo -e "${BOLD}协议栈 / Stack:${NC} $stack"
    if [ "$has_xhttp" = 1 ]; then
        echo "  传输 transport: ${network:-http}（xhttpSettings 已启用）"
    else
        echo "  传输 transport: ${network:-tcp}"
    fi
    echo "  安全 security:  ${security:-none}"
    if [ -n "$flow" ]; then
        echo "  流控 flow:      $flow"
    else
        echo "  流控 flow:      无（未启用 XTLS Vision，本项目不带流控）"
    fi

    if [ "$has_xhttp" = 1 ]; then
        local xmode xpath xhost
        xmode=$(json_str "$cfg" mode)
        xpath=$(json_str "$cfg" path)
        xhost=$(json_str "$cfg" host)
        echo "  XHTTP:          mode=${xmode:-auto}  path=${xpath:-/}  host=${xhost:-*(任意)}"
    fi

    echo ""
    ids=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" | sed -E 's/.*"([^"]*)"$/\1/')
    n_ids=$(echo "$ids" | grep -c . 2>/dev/null || true)
    echo -e "${BOLD}客户端 / Clients:${NC}"
    if [ -z "$ids" ]; then
        echo "  (未找到 UUID)"
    else
        echo "$ids" | while read -r id; do
            [ -n "$id" ] && echo "  UUID: $id"
        done
        [ "$n_ids" -gt 1 ] && echo "  共 $n_ids 个客户端"
    fi

    if [ "$security" = "reality" ]; then
        local dest snis sid pk pub fp
        dest=$(json_str "$cfg" dest)
        snis=$(json_arr "$cfg" serverNames)
        sid=$(json_arr "$cfg" shortIds)
        pk=$(json_str "$cfg" privateKey)
        pub=$(json_str "$cfg" publicKey)
        fp=$(json_str "$cfg" fingerprint)
        echo ""
        echo -e "${BOLD}REALITY:${NC}"
        echo "  dest:        ${dest}"
        echo "  serverNames: ${snis}"
        echo "  privateKey:  $(mask_key "$pk")（已设置）"
        if [ -n "$pub" ]; then
            echo "  publicKey:   $pub"
        else
            echo "  publicKey:   (未写入配置，客户端可用 keygen 由私钥再生成)"
        fi
        echo "  shortIds:    ${sid}"
        echo "  fingerprint: ${fp:-chrome}"
    fi

    local tfo tnd app
    tfo=$(json_bool "$cfg" tcpFastOpen);    [ -z "$tfo" ] && tfo=true
    tnd=$(json_bool "$cfg" tcpNoDelay);     [ -z "$tnd" ] && tnd=true
    app=$(json_bool "$cfg" acceptProxyProtocol); [ -z "$app" ] && app=false
    echo ""
    echo -e "${BOLD}sockopt:${NC} tcpFastOpen=$(bool_cn "$tfo")  tcpNoDelay=$(bool_cn "$tnd")  acceptProxyProtocol=$(bool_cn "$app")"

    echo ""
    if grep -q '"performance"' "$cfg"; then
        local wt mc sw cw st sb pb ub d="默认"
        wt=$(json_num "$cfg" workerThreads)
        mc=$(json_num "$cfg" maxConnections)
        sw=$(json_num "$cfg" h2StreamWindowKb)
        cw=$(json_num "$cfg" h2ConnectionWindowKb)
        st=$(json_num "$cfg" h2MaxConcurrentStreams)
        sb=$(json_num "$cfg" h2SendBufferKb)
        pb=$(json_num "$cfg" pipeBufferKb)
        ub=$(json_num "$cfg" udpSocketBufferKb)
        echo -e "${BOLD}performance:${NC}"
        echo "  workerThreads=${wt:-$d}  maxConnections=${mc:-$d}  h2MaxConcurrentStreams=${st:-$d}"
        echo "  h2StreamWindowKb=${sw:-$d}  h2ConnectionWindowKb=${cw:-$d}"
        echo "  h2SendBufferKb=${sb:-$d}  pipeBufferKb=${pb:-$d}  udpSocketBufferKb=${ub:-$d}"
    else
        echo -e "${BOLD}performance:${NC} 配置文件中未设置（使用内置默认值）"
    fi

    # 客户端配置一致性检查
    echo ""
    echo -e "${BOLD}客户端配置 / Client configs:${NC}"
    local cf cport
    cf="$dir/client-config.json"
    if [ -f "$cf" ]; then
        cport=$(client_json_port "$cf")
        if [ -z "$cport" ]; then
            echo "  client-config.json  已存在（未读到端口）"
        elif [ "$cport" = "$port" ]; then
            echo -e "  client-config.json  端口 $cport ${GREEN}✓ 与服务端一致${NC}"
        else
            echo -e "  client-config.json  端口 $cport ${RED}✗ 与服务端不一致，需更新${NC}"
        fi
    else
        echo "  client-config.json  不存在"
    fi
    cf="$dir/clash-verge.yaml"
    if [ -f "$cf" ]; then
        cport=$(client_yaml_port "$cf")
        if [ -z "$cport" ]; then
            echo "  clash-verge.yaml    已存在（未读到节点端口）"
        elif [ "$cport" = "$port" ]; then
            echo -e "  clash-verge.yaml    端口 $cport ${GREEN}✓ 与服务端一致${NC}"
        else
            echo -e "  clash-verge.yaml    端口 $cport ${RED}✗ 与服务端不一致，需更新${NC}"
        fi
    else
        echo "  clash-verge.yaml    不存在"
    fi

    if [ "$(grep -c '"port"' "$cfg")" -gt 1 ]; then
        echo ""
        warn "配置文件里有多个 port，本工具只显示/修改第一个入站"
    fi

    echo ""
    echo -e "${BLUE}-----------------------------------------${NC}"
    echo "改端口 / Change port: bash manage.sh set-port <新端口>"
    echo "  只改端口，UUID / 密钥 / 传输方式保持不变"
}

# ---------------------------------------------------------------------------
# set-port
# ---------------------------------------------------------------------------

# 同步客户端配置里的端口（只改节点端口，本地 socks / mixed-port 不动）
sync_client_configs() {
    local dir=$1 new=$2 ts=$3 f b
    f="$dir/client-config.json"
    if [ -f "$f" ]; then
        if [ "$(client_json_port "$f")" = "$new" ]; then
            ok "client-config.json 端口已是 ${new}，无需修改"
        else
            b=$(backup "$f" "$ts")
            if edit_client_json_port "$f" "$new" && [ "$(client_json_port "$f")" = "$new" ]; then
                ok "客户端配置已更新: client-config.json（备份 ${b}）"
            else
                [ -n "$b" ] && cp -p "$b" "$f"
                warn "client-config.json 更新失败，已跳过"
            fi
        fi
    fi
    f="$dir/clash-verge.yaml"
    if [ -f "$f" ]; then
        if [ "$(client_yaml_port "$f")" = "$new" ]; then
            ok "clash-verge.yaml 端口已是 ${new}，无需修改"
        else
            b=$(backup "$f" "$ts")
            if edit_yaml_port "$f" "$new" && [ "$(client_yaml_port "$f")" = "$new" ]; then
                ok "客户端配置已更新: clash-verge.yaml（备份 ${b}）"
            else
                [ -n "$b" ] && cp -p "$b" "$f"
                warn "clash-verge.yaml 更新失败，已跳过"
            fi
        fi
    fi
}

cmd_set_port() {
    local cfg=$1 new=$2 dir ts old backup_file
    local sync_clients=$3 no_restart=$4

    dir=$(dirname "$cfg")
    old=$(json_num "$cfg" port)
    [ -z "$old" ] && die "没在 $cfg 里找到入站端口（\"port\"）"

    local n_ports
    n_ports=$(grep -c '"port"' "$cfg")
    if [ "$n_ports" -gt 1 ]; then
        warn "配置文件里有 ${n_ports} 个 port，只修改第一个入站端口"
    fi

    if [ "$old" = "$new" ]; then
        echo "端口已经是 ${new}，服务端无需修改 / nothing to do"
        # 服务端没动，但客户端配置可能还是旧端口，顺手对齐
        if [ "$sync_clients" = 1 ]; then
            sync_client_configs "$dir" "$new" "$(date +%Y%m%d-%H%M%S)"
        fi
        return 0
    fi

    if port_in_use "$new"; then
        warn "端口 $new 已被占用 / port $new is in use:"
        port_holder "$new"
        die "请换一个端口，或先停掉占用它的进程"
    fi

    ts=$(date +%Y%m%d-%H%M%S)

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Xray-Lite 修改端口 / Change Port${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "配置文件: $cfg"
    echo "端口:     $old -> $new"
    echo ""

    backup_file=$(backup "$cfg" "$ts") || die "备份失败，未做任何修改: $cfg"
    ok "已备份: $backup_file"

    if ! edit_inbound_port "$cfg" "$new"; then
        cp -p "$backup_file" "$cfg"
        die "写入失败，已从备份恢复 / write failed, restored"
    fi

    # 回读确认，避免 awk 改错位置
    if [ "$(json_num "$cfg" port)" != "$new" ]; then
        cp -p "$backup_file" "$cfg"
        die "回读端口不一致，已从备份恢复 / verification failed, restored"
    fi
    ok "服务端端口已改为 ${new}（UUID / 密钥 / 传输方式未改动）"

    # 同步客户端配置
    echo ""
    if [ "$sync_clients" = 1 ]; then
        sync_client_configs "$dir" "$new" "$ts"
    else
        warn "跳过客户端配置更新 (--no-clients)，记得手动把客户端端口改成 $new"
    fi

    echo ""
    open_firewall "$new" || true

    if [ "$no_restart" = 1 ]; then
        warn "跳过重启 (--no-restart)，新端口要重启后生效"
    else
        echo ""
        restart_service "$dir" || true
        if [ "$EUID" -eq 0 ]; then
            sleep 2
            if port_in_use "$new"; then
                ok "新端口 $new 已在监听"
            else
                warn "没有检测到 $new 在监听，请检查服务状态和日志"
            fi
        fi
    fi

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  完成 / Done: 端口 $old -> $new${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo "  配置备份: $backup_file"
    echo ""
    echo -e "${YELLOW}还需要你确认 / Check these:${NC}"
    echo "  1. 云厂商安全组 / 控制台防火墙：放行 TCP ${new}（旧端口被封时要在这里加）"
    if [ -f "$dir/client-config.json" ] || [ -f "$dir/clash-verge.yaml" ]; then
        echo "  2. 客户端：重新导入 $dir/clash-verge.yaml 或 $dir/client-config.json，"
        echo "     或在客户端里直接把端口改成 ${new}"
    else
        echo "  2. 客户端：把节点端口改成 ${new}"
    fi
    echo "  3. 旧端口 $old 的防火墙规则仍然保留，需要的话自行删除"
}

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------

CMD=""
ARGS=()
CONFIG=""
SYNC_CLIENTS=1
NO_RESTART=0

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config)
            [ $# -ge 2 ] || die "-c 需要一个路径参数"
            CONFIG="$2"
            shift 2
            ;;
        --no-restart)
            NO_RESTART=1
            shift
            ;;
        --no-clients)
            SYNC_CLIENTS=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "未知参数 / unknown option: $1（用 --help 查看用法）"
            ;;
        *)
            if [ -z "$CMD" ]; then
                CMD="$1"
            else
                ARGS[${#ARGS[@]}]="$1"
            fi
            shift
            ;;
    esac
done

[ -z "$CMD" ] && CMD="show"

# 定位配置文件
if [ -z "$CONFIG" ]; then
    if [ -n "$XRAY_LITE_CONFIG" ]; then
        CONFIG="$XRAY_LITE_CONFIG"
    elif [ -f "/opt/xray-lite/config.json" ]; then
        CONFIG="/opt/xray-lite/config.json"
    elif [ -f "./config.json" ]; then
        CONFIG="./config.json"
    else
        CONFIG="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/config.json"
    fi
fi

[ -f "$CONFIG" ] || die "找不到配置文件: ${CONFIG}（用 -c 指定，或设置 XRAY_LITE_CONFIG）"

case "$CMD" in
    show)
        show_config "$CONFIG"
        ;;
    set-port|port)
        [ "${#ARGS[@]}" -ge 1 ] || die "用法: bash manage.sh set-port <端口>"
        NEWPORT="${ARGS[0]}"
        case "$NEWPORT" in
            ''|*[!0-9]*) die "端口必须是数字: $NEWPORT" ;;
        esac
        # 去掉前导 0，避免 bash 把它当八进制
        NEWPORT=$(echo "$NEWPORT" | sed 's/^0*//')
        [ -z "$NEWPORT" ] && NEWPORT=0
        if [ "$NEWPORT" -lt 1 ] || [ "$NEWPORT" -gt 65535 ]; then
            die "端口范围必须是 1-65535: $NEWPORT"
        fi
        cmd_set_port "$CONFIG" "$NEWPORT" "$SYNC_CLIENTS" "$NO_RESTART"
        ;;
    *)
        die "未知命令 / unknown command: ${CMD}（可用: show, set-port）"
        ;;
esac
