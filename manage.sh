#!/bin/bash

# Xray-Lite Management Tool
# Xray-Lite 管理工具
#
# 只做这些事 / jobs:
#   1. show        打印当前生效的配置（协议栈、端口、UUID、Reality、XHTTP、性能参数…）
#   2. set-port    只改监听端口，UUID / 私钥 / shortId / 传输方式等一律不动
#   3. set-domain  只改 Reality 伪装域名（dest / serverNames），密钥与 UUID 不动
#   4. export      导出新生成的配置文件，方便下载到本地
#   5. rebuild     完全重建：清干净旧服务与残留，重新生成 UUID / 密钥 / 全部配置
#
# Usage / 用法:
#   bash manage.sh                                  # 等同 show
#   bash manage.sh show
#   bash manage.sh show -c /opt/xray-lite/config.json
#   bash manage.sh set-port 2083
#   bash manage.sh set-port 2083 --no-restart       # 只改文件，不重启服务
#   bash manage.sh set-port 2083 --no-clients       # 不更新客户端配置
#   bash manage.sh set-domain swdist.apple.com
#   bash manage.sh export
#   bash manage.sh export /root/my-configs --tar
#   bash manage.sh rebuild
#   bash manage.sh rebuild --yes
#
# Options / 参数:
#   -c, --config PATH   指定 config.json（默认 /opt/xray-lite/config.json）
#                       也可用环境变量 XRAY_LITE_CONFIG 指定
#       --no-restart    set-port / set-domain 改完不重启服务
#       --no-clients    set-port / set-domain 不更新同目录下的客户端配置
#       --tar           export 时额外打包成 tar.gz
#       -y, --yes       rebuild 时跳过确认
#       --installer P   rebuild 时使用指定的 install.sh（离线 / 自建源）
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
REPO="dongjiahong/xray-lite"
INSTALL_URL="https://raw.githubusercontent.com/${REPO}/main/install.sh"

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
  manage.sh set-domain <域名>         只改 Reality 伪装域名 (dest / serverNames)
  manage.sh export [目录]             导出配置文件，方便下载到本地
  manage.sh rebuild                   完全重建（清干净后重新生成全部配置）

参数 / Options:
  -c, --config PATH   指定 config.json（默认 /opt/xray-lite/config.json）
                      也可用环境变量 XRAY_LITE_CONFIG 指定
  --no-restart        set-port / set-domain 改完文件后不重启服务
  --no-clients        set-port / set-domain 不更新 client-config.json / clash-verge.yaml
  --tar               export 时额外打包为 tar.gz
  -y, --yes           rebuild 时跳过确认（非交互环境必须加）
  --installer PATH    rebuild 时使用指定的 install.sh（离线 / 自建源）

示例 / Examples:
  manage.sh
  manage.sh show
  manage.sh show -c /root/config.json
  manage.sh set-port 2083
  manage.sh set-port 2053 --no-restart
  manage.sh set-domain swdist.apple.com
  manage.sh set-domain addons.mozilla.org:443 --no-restart
  manage.sh export
  manage.sh export /root/out --tar
  manage.sh rebuild
  manage.sh rebuild --yes

默认值 / Defaults:
  安装脚本默认端口 2083、伪装域名 swdist.apple.com:443
  推荐端口：2083 8443 2053 2087 2096
EOF
}

# ---------------------------------------------------------------------------
# JSON / YAML 读取（不依赖 jq；只认 install.sh 生成的扁平结构）
# ---------------------------------------------------------------------------

# 读取字符串字段：取第一个匹配的值
# 用 grep -o 逐个抽取再取首个，压缩成一行的 JSON 也不会取到后面的同名字段
json_str() {
    grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null |
        head -n 1 |
        sed -E "s/^\"[^\"]*\"[[:space:]]*:[[:space:]]*\"(.*)\"$/\1/"
}

# 读取数字字段
json_num() {
    grep -oE "\"$2\"[[:space:]]*:[[:space:]]*[0-9]+" "$1" 2>/dev/null |
        head -n 1 |
        sed -E "s/^\"[^\"]*\"[[:space:]]*:[[:space:]]*//"
}

# 读取布尔字段
json_bool() {
    grep -oE "\"$2\"[[:space:]]*:[[:space:]]*(true|false)" "$1" 2>/dev/null |
        head -n 1 |
        sed -E "s/^\"[^\"]*\"[[:space:]]*:[[:space:]]*//"
}

# 读取 YAML 标量（去掉包裹的引号）
yaml_str() {
    sed -n -E "s/^[[:space:]]*$2:[[:space:]]*\"?([^\"[:space:]]*)\"?[[:space:]]*$/\1/p" "$1" | head -n 1
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
# 按整份文本定位，单行压缩的 JSON 上也不会读到前面 inbounds 的 socks 端口
client_json_port() {
    awk '
        { buf = buf $0 "\n" }
        END {
            p = index(buf, "\"vnext\"")
            if (p == 0) exit 1
            seg = substr(buf, p)
            if (!match(seg, "\"port\"[ \t]*:[ \t]*[0-9]+")) exit 1
            s = substr(seg, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", s)
            print s
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
# 配置文件修改
#
# 统一按「整份文本」定位后再替换，而不是逐行处理：
# 逐行写法在压缩成单行的 JSON 上会丢行前缀，或者改到前面同名字段。
# ---------------------------------------------------------------------------

# 替换第一个 key 的标量值（字符串或数字），其余字节保持不变
#   json_set_scalar <file> <key> <value> [anchor]
# anchor 非空时，只在该字段之后查找（例如 "vnext" 之后的 port）
json_set_scalar() {
    local file=$1 key=$2 val=$3 anchor="${4:-}" tmp rc
    tmp="${file}.tmp.$$"
    cp -p "$file" "$tmp" || return 1
    LC_ALL=C awk -v k="$key" -v v="$val" -v a="$anchor" '
        { buf = buf $0 "\n" }
        END {
            start = 1
            if (a != "") {
                p = index(buf, "\"" a "\"")
                if (p == 0) exit 3
                start = p
            }
            seg = substr(buf, start)
            if (!match(seg, "\"" k "\"[ \t]*:[ \t]*(\"[^\"]*\"|[0-9]+)")) exit 3

            abs = start + RSTART - 1
            m = substr(seg, RSTART, RLENGTH)
            colon = index(m, ":")
            head = substr(m, 1, colon)              # "key":
            if (substr(m, colon + 1) ~ /^[ \t]*"/) {
                newm = head " \"" v "\""
            } else {
                newm = head " " v
            }
            printf "%s", substr(buf, 1, abs - 1) newm substr(buf, abs + RLENGTH)
        }
    ' "$file" > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
    mv "$tmp" "$file"
}

# 替换第一个 key 的数组值，按原格式（多行 / 单行）输出，其余字节保持不变
#   json_set_array <file> <key> <anchor> <v1> [v2 ...]
json_set_array() {
    local file=$1 key=$2 anchor=$3 tmp rc
    shift 3
    local vals="" v
    for v in "$@"; do
        vals="${vals}${v}"$'\n'
    done
    [ -z "$vals" ] && return 1

    tmp="${file}.tmp.$$"
    cp -p "$file" "$tmp" || return 1
    XLA_VALS="$vals" LC_ALL=C awk -v k="$key" -v a="$anchor" '
        { buf = buf $0 "\n" }
        END {
            start = 1
            if (a != "") {
                p = index(buf, "\"" a "\"")
                if (p == 0) exit 3
                start = p
            }
            kp = index(substr(buf, start), "\"" k "\"")
            if (kp == 0) exit 3
            kp = start + kp - 1

            rest = substr(buf, kp)
            ob = index(rest, "[")
            if (ob == 0) exit 3
            after_open = substr(rest, ob + 1)
            cb = index(after_open, "]")
            if (cb == 0) exit 3

            # 原数组所在区间（含方括号）是否跨行
            region = substr(rest, ob, cb + 1)
            multiline = (region ~ /\n/)

            n = split(ENVIRON["XLA_VALS"], raw, "\n")
            m = 0
            for (i = 1; i <= n; i++) if (raw[i] != "") v[++m] = raw[i]

            if (multiline) {
                # 沿用 key 所在行的缩进
                line_start = kp
                while (line_start > 1 && substr(buf, line_start - 1, 1) != "\n") line_start--
                lead = substr(buf, line_start)
                match(lead, /^[ \t]*/)
                indent = substr(lead, 1, RLENGTH)

                repl = ""
                for (i = 1; i <= m; i++)
                    repl = repl indent "  \"" v[i] "\"" (i == m ? "\n" : ",\n")
                repl = "[\n" repl indent "]"
            } else {
                repl = "["
                for (i = 1; i <= m; i++)
                    repl = repl (i > 1 ? ", " : "") "\"" v[i] "\""
                repl = repl "]"
            }

            abs = kp + ob - 1
            printf "%s", substr(buf, 1, abs - 1) repl substr(buf, abs + cb + 1)
        }
    ' "$file" > "$tmp"
    rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
    mv "$tmp" "$file"
}

# 服务端 config.json：只改第一个 port（即第一个入站的监听端口）
edit_inbound_port() {
    json_set_scalar "$1" port "$2"
}

# client-config.json：只改 vnext 里的 port（inbounds 的 socks 端口 1080 不动）
edit_client_json_port() {
    json_set_scalar "$1" port "$2" "vnext"
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
    local file=$1 ts=$2 target i=1
    target="${file}.bak.${ts}"
    # 同一秒内连续改动时避免覆盖上一个备份
    while [ -e "$target" ]; do
        i=$((i + 1))
        target="${file}.bak.${ts}.${i}"
    done
    cp -p "$file" "$target" || return 1
    echo "$target"
}

# 改 YAML 里的标量： "  key: 旧值" -> "  key: 新值"
edit_yaml_str() {
    local file=$1 key=$2 val=$3 tmp rc
    tmp="${file}.tmp.$$"
    cp -p "$file" "$tmp" || return 1
    LC_ALL=C awk -v k="$key" -v v="$val" '
        !done && $0 ~ "^[[:space:]]*" k ":" {
            before = $0
            sub(k ":.*$", "", before)
            print before k ": " v
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

# 简单判断是否为 IPv4 字面量
is_ipv4() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
        *.*.*.*) return 0 ;;
        *) return 1 ;;
    esac
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
    echo "改端口 / Change port:     bash manage.sh set-port <新端口>"
    echo "改伪装域名 / Change SNI:  bash manage.sh set-domain <域名>"
    echo "导出配置 / Export:        bash manage.sh export"
    echo "完全重建 / Rebuild:       bash manage.sh rebuild"
    echo "  前三项只改对应字段，UUID / 密钥 / 传输方式保持不变"
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
# set-domain
# ---------------------------------------------------------------------------

# 同步客户端配置里的 SNI / servername
sync_client_domain() {
    local dir=$1 dom=$2 ts=$3 f b
    f="$dir/client-config.json"
    if [ -f "$f" ]; then
        if [ -z "$(json_str "$f" serverName)" ]; then
            warn "client-config.json 里没有 serverName 字段，跳过（请手动检查）"
        elif [ "$(json_str "$f" serverName)" = "$dom" ]; then
            ok "client-config.json 域名已是 ${dom}，无需修改"
        else
            b=$(backup "$f" "$ts")
            if json_set_scalar "$f" serverName "$dom" &&
               [ "$(json_str "$f" serverName)" = "$dom" ]; then
                ok "客户端配置已更新: client-config.json（备份 ${b}）"
            else
                [ -n "$b" ] && cp -p "$b" "$f"
                warn "client-config.json 更新失败，已跳过"
            fi
        fi
    fi

    f="$dir/clash-verge.yaml"
    if [ -f "$f" ]; then
        if [ -z "$(yaml_str "$f" servername)" ]; then
            warn "clash-verge.yaml 里没有 servername 字段，跳过（请手动检查）"
        elif [ "$(yaml_str "$f" servername)" = "$dom" ]; then
            ok "clash-verge.yaml 域名已是 ${dom}，无需修改"
        else
            b=$(backup "$f" "$ts")
            if edit_yaml_str "$f" servername "$dom" &&
               [ "$(yaml_str "$f" servername)" = "$dom" ]; then
                ok "客户端配置已更新: clash-verge.yaml（备份 ${b}）"
            else
                [ -n "$b" ] && cp -p "$b" "$f"
                warn "clash-verge.yaml 更新失败，已跳过"
            fi
        fi
    fi
}

cmd_set_domain() {
    local cfg=$1 input=$2 dir ts dom dport
    local old_dest old_dom old_dport new_dest backup_file failed=0
    local sync_clients=$3 no_restart=$4

    dir=$(dirname "$cfg")

    # 解析 域名 或 域名:端口
    case "$input" in
        '') die "域名不能为空" ;;
        *[!A-Za-z0-9._:-]*) die "域名格式看起来不对: ${input}" ;;
    esac
    if [ "$(echo "$input" | tr -cd ':' | wc -c | tr -d ' ')" -gt 1 ]; then
        die "不支持 IPv6 形式的 dest，请用 域名 或 域名:端口"
    fi
    if [ "$input" != "${input%%:*}" ]; then
        dom="${input%%:*}"
        dport="${input##*:}"
    else
        dom="$input"
        dport=""
    fi
    [ -z "$dom" ] && die "域名不能为空"
    if [ -n "$dport" ]; then
        case "$dport" in
            ''|*[!0-9]*) die "端口必须是数字: ${dport}" ;;
        esac
        if [ "$dport" -lt 1 ] || [ "$dport" -gt 65535 ]; then
            die "端口范围必须是 1-65535: ${dport}"
        fi
    fi

    old_dest=$(json_str "$cfg" dest)
    if [ -z "$old_dest" ]; then
        die "配置里没有 realitySettings.dest，这个配置不是在用 Reality，无法改域名"
    fi

    # 没指定端口时沿用原 dest 的端口
    old_dom="${old_dest%%:*}"
    if [ "$old_dest" != "${old_dest%%:*}" ]; then
        old_dport="${old_dest##*:}"
    else
        old_dport="443"
    fi
    [ -z "$dport" ] && dport="$old_dport"
    new_dest="${dom}:${dport}"

    if [ "$old_dest" = "$new_dest" ]; then
        echo "dest 已经是 ${new_dest}，服务端无需修改 / nothing to do"
        if [ "$sync_clients" = 1 ]; then
            sync_client_domain "$dir" "$dom" "$(date +%Y%m%d-%H%M%S)"
        fi
        return 0
    fi

    ts=$(date +%Y%m%d-%H%M%S)

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Xray-Lite 修改伪装域名 / Change Domain${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "配置文件: $cfg"
    echo "域名:     ${old_dom} -> ${dom}"
    echo "dest:     ${old_dest} -> ${new_dest}"
    echo ""

    backup_file=$(backup "$cfg" "$ts") || die "备份失败，未做任何修改: $cfg"
    ok "已备份: $backup_file"

    json_set_scalar "$cfg" dest "$new_dest" || failed=1

    if [ "$failed" = 0 ]; then
        if is_ipv4 "$dom"; then
            json_set_array "$cfg" serverNames "" "$dom" || failed=1
        else
            json_set_array "$cfg" serverNames "" "$dom" "*.${dom}" || failed=1
        fi
    fi

    if [ "$failed" = 0 ] && [ "$(json_str "$cfg" dest)" != "$new_dest" ]; then
        failed=1
    fi

    if [ "$failed" = 1 ]; then
        cp -p "$backup_file" "$cfg"
        die "写入失败，已从备份恢复 / write failed, restored"
    fi
    ok "服务端 dest / serverNames 已改为 ${dom}（UUID / 密钥未改动）"

    # XHTTP 的 host 如果原本填了具体域名，一起跟进；留空表示任意域名，不动
    local xhost
    xhost=$(json_str "$cfg" host)
    if [ -n "$xhost" ] && [ "$xhost" != "$dom" ]; then
        if json_set_scalar "$cfg" host "$dom" "xhttpSettings"; then
            ok "XHTTP host 已同步为 ${dom}"
        else
            warn "XHTTP host 更新失败，请手动检查 xhttpSettings.host"
        fi
    fi

    echo ""
    if [ "$sync_clients" = 1 ]; then
        sync_client_domain "$dir" "$dom" "$ts"
    else
        warn "跳过客户端配置更新 (--no-clients)，记得手动把 SNI 改成 ${dom}"
    fi

    if [ "$no_restart" = 1 ]; then
        echo ""
        warn "跳过重启 (--no-restart)，新域名要重启后生效"
    else
        echo ""
        restart_service "$dir" || true
    fi

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  完成 / Done: 域名 ${old_dom} -> ${dom}${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo "  配置备份: $backup_file"
    echo ""
    echo -e "${YELLOW}还需要你确认 / Check these:${NC}"
    echo "  1. 新域名要满足 Reality 的要求：支持 TLS 1.3、HTTP/2，证书有效，"
    echo "     且不在国内被墙（用 ${dom}:${dport} 直连能访问到真实网站）"
    echo "  2. 客户端 SNI 必须同步：重新导入 $dir/clash-verge.yaml 或 $dir/client-config.json"
    echo "  3. UUID / 私钥 / shortId 都没变，客户端只需改 servername 即可"
    echo ""
    echo "  导出改好的配置: bash manage.sh export"
}

# ---------------------------------------------------------------------------
# export
# ---------------------------------------------------------------------------

# 从 config.json 拼一条 vless:// 链接
build_vless_link() {
    local cfg=$1 addr=$2
    local uuid port sni pbk sid fp network flow link query
    local xpath xhost xmode

    uuid=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$cfg" |
           sed -E 's/.*"([^"]*)"$/\1/' | head -n 1)
    port=$(json_num "$cfg" port)
    sni=$(json_arr "$cfg" serverNames | cut -d, -f1 | sed 's/^[[:space:]]*//')
    pbk=$(json_str "$cfg" publicKey)
    sid=$(json_arr "$cfg" shortIds | cut -d, -f1 | sed 's/^[[:space:]]*//')
    fp=$(json_str "$cfg" fingerprint)
    network=$(json_str "$cfg" network)
    flow=$(json_str "$cfg" flow)

    [ -z "$fp" ] && fp="chrome"
    if [ -z "$uuid" ] || [ -z "$port" ] || [ "$port" = "0" ]; then
        return 1
    fi

    local security
    security=$(json_str "$cfg" security)
    [ -z "$security" ] && security="none"

    query="encryption=none&security=${security}"
    [ -n "$sni" ] && query="${query}&sni=${sni}"
    [ -n "$fp" ] && query="${query}&fp=${fp}"
    [ -n "$pbk" ] && query="${query}&pbk=${pbk}"
    [ -n "$sid" ] && query="${query}&sid=${sid}"

    if grep -q '"xhttpSettings"' "$cfg"; then
        xpath=$(json_str "$cfg" path); [ -z "$xpath" ] && xpath="/"
        xhost=$(json_str "$cfg" host)
        xmode=$(json_str "$cfg" mode); [ -z "$xmode" ] && xmode="auto"
        query="${query}&type=xhttp&path=${xpath}&mode=${xmode}"
        [ -n "$xhost" ] && query="${query}&host=${xhost}"
    else
        query="${query}&type=${network:-tcp}"
    fi
    [ -n "$flow" ] && query="${query}&flow=${flow}"

    link="vless://${uuid}@${addr}:${port}?${query}#xray-lite"
    printf '%s\n' "$link"
}

cmd_export() {
    local cfg=$1 outdir=$2 do_tar=$3
    local dir ts addr f n=0 link

    dir=$(dirname "$cfg")
    ts=$(date +%Y%m%d-%H%M%S)

    if [ -z "$outdir" ]; then
        outdir="${HOME:-/root}/xray-lite-export-${ts}"
    fi

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Xray-Lite 导出配置 / Export Configs${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "来源目录: $dir"
    echo "导出目录: $outdir"
    echo ""

    mkdir -p "$outdir" || die "无法创建目录: ${outdir}"

    for f in config.json client-config.json clash-verge.yaml; do
        [ -f "$dir/$f" ] || continue
        cp -p "$dir/$f" "$outdir/$f" || die "复制失败: $f"
        echo "  ✓ $f"
        n=$((n + 1))
    done
    [ "$n" -eq 0 ] && die "没有可导出的配置文件（$dir 里找不到 config.json 等）"

    # config.json 含 Reality 私钥
    chmod 600 "$outdir/config.json" 2>/dev/null || true

    # 服务器地址：优先客户端配置里已有的，再尝试在线探测
    if [ -f "$dir/client-config.json" ]; then
        addr=$(json_str "$dir/client-config.json" address)
    fi
    if [ -z "$addr" ] && command -v curl >/dev/null 2>&1; then
        addr=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || true)
    fi
    [ -z "$addr" ] && addr="<你的服务器IP>"

    link=$(build_vless_link "$cfg" "$addr" || true)
    if [ -n "$link" ]; then
        printf '%s\n' "$link" > "$outdir/vless-link.txt"
        chmod 600 "$outdir/vless-link.txt" 2>/dev/null || true
        echo "  ✓ vless-link.txt"
    else
        warn "没能拼出 VLESS 链接（缺少 UUID 或端口），跳过"
    fi

    echo ""

    local tarfile=""
    if [ "$do_tar" = 1 ]; then
        if command -v tar >/dev/null 2>&1; then
            tarfile="${outdir%/}.tar.gz"
            if ( cd "$(dirname "$outdir")" && tar -czf "$tarfile" "$(basename "$outdir")" ); then
                chmod 600 "$tarfile" 2>/dev/null || true
                ok "已打包: $tarfile"
            else
                warn "打包失败，文件已在目录里，可直接用目录"
                tarfile=""
            fi
        else
            warn "系统没有 tar，跳过打包"
        fi
        echo ""
    fi

    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  导出完成 / Export Complete${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${BLUE}下载到本地 / Download:${NC}"
    if [ -n "$tarfile" ]; then
        echo "  scp root@${addr}:${tarfile} ."
    else
        echo "  scp -r root@${addr}:${outdir} ."
    fi
    echo ""

    if [ -n "$link" ]; then
        echo -e "${BLUE}VLESS 链接（可直接导入客户端）:${NC}"
        echo "  $link"
        echo ""
    fi

    echo -e "${YELLOW}注意 / Note: config.json 含 Reality 私钥，vless-link.txt 含 UUID，${NC}"
    echo -e "${YELLOW}别上传到公开仓库或聊天群；用不着就把导出目录删掉。${NC}"
    echo ""
    echo "  删除导出目录: rm -rf ${outdir}"
}

# ---------------------------------------------------------------------------
# rebuild
# ---------------------------------------------------------------------------

# 备份现有配置到 ~/xray-lite-backup-<时间戳>，与 uninstall.sh 的命名保持一致
backup_configs() {
    local dir=$1 ts=$2 dest="${HOME:-/root}/xray-lite-backup-$2" f n=0 i=1
    # 同一秒内重复重建时避免覆盖上一份备份
    while [ -e "$dest" ]; do
        i=$((i + 1))
        dest="${HOME:-/root}/xray-lite-backup-$2.$i"
    done
    for f in config.json client-config.json clash-verge.yaml; do
        [ -f "$dir/$f" ] || continue
        mkdir -p "$dest" || return 1
        cp -p "$dir/$f" "$dest/$f" || return 1
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] && printf '%s\n' "$dest"
    return 0
}

# 是否还有本安装目录的 vless-server 进程
process_alive() {
    local dir=$1
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$dir/vless-server" >/dev/null 2>&1
        return $?
    fi
    # busybox 没有 pgrep 时用 ps 兜底
    ps 2>/dev/null | grep -F "$dir/vless-server" | grep -qv grep
}

# 停掉所有可能还在跑的服务形态
stop_all() {
    local dir=$1 pid i

    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi

    if [ -x "$dir/run.sh" ]; then
        "$dir/run.sh" stop >/dev/null 2>&1 || true
    fi

    if [ -f "$dir/xray-lite.pid" ]; then
        pid=$(cat "$dir/xray-lite.pid" 2>/dev/null || true)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    fi

    # 只杀本安装目录下的进程，避免误伤别的 vless-server
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "$dir/vless-server" 2>/dev/null || true
    fi

    for i in 1 2 3 4 5 6 7 8 9 10; do
        process_alive "$dir" || return 0
        sleep 1
    done

    warn "进程仍未退出，尝试强制结束 / forcing kill"
    if command -v pkill >/dev/null 2>&1; then
        pkill -9 -f "$dir/vless-server" 2>/dev/null || true
    elif [ -n "$pid" ]; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    sleep 1
    ! process_alive "$dir"
}

# 清理上一次安装留下的所有痕迹（保留 manage.sh 自身）
clean_residue() {
    local dir=$1 unit="/etc/systemd/system/${SERVICE_NAME}.service"
    local jd="/etc/systemd/journald.conf.d/${SERVICE_NAME}.conf"

    if [ -f "$unit" ]; then
        rm -f "$unit"
        ok "已删除 systemd unit: $unit"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
        fi
    fi

    if [ -f "$jd" ]; then
        rm -f "$jd"
        rmdir "$(dirname "$jd")" 2>/dev/null || true
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart systemd-journald >/dev/null 2>&1 || true
        fi
        ok "已删除 journald 日志轮转配置"
    fi

    local f
    for f in run.sh xray-lite.pid xray-lite.log xray-lite.log.1 \
             vless-server.new keygen.new manage.sh.new install.sh.new; do
        if [ -e "$dir/$f" ]; then
            rm -f "$dir/$f"
            ok "已删除 $f"
        fi
    done

    for f in config.json client-config.json clash-verge.yaml; do
        [ -e "$dir/$f" ] && rm -f "$dir/$f"
    done

    # 各类时间戳备份
    rm -f "$dir"/*.bak.* 2>/dev/null || true

    if [ -L /usr/local/bin/xray-lite ]; then
        rm -f /usr/local/bin/xray-lite
        ok "已删除快捷命令 /usr/local/bin/xray-lite"
    fi
}

# 找到可用的 install.sh：优先参数指定，其次本地副本，最后联网下载
resolve_installer() {
    local dir=$1 custom=$2 tmp
    if [ -n "$custom" ]; then
        [ -f "$custom" ] || return 1
        printf '%s\n' "$custom"
        return 0
    fi
    if [ -f "$dir/install.sh" ]; then
        printf '%s\n' "$dir/install.sh"
        return 0
    fi

    tmp="${TMPDIR:-/tmp}/xray-lite-install.$$"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$INSTALL_URL" -o "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" "$INSTALL_URL" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
    else
        return 1
    fi
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 1
    fi
    printf '%s\n' "$tmp"
}

cmd_rebuild() {
    local cfg=$1 assume_yes=$2 custom=$3
    local dir ts backup_dir installer rc

    dir=$(dirname "$cfg")

    if [ "$EUID" -ne 0 ]; then
        die "rebuild 需要 root（要停服务、删 unit、重装服务）"
    fi

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}  Xray-Lite 完全重建 / Rebuild${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "安装目录: ${dir}"
    echo ""
    echo -e "${YELLOW}这会删除并重新生成 / This will wipe and regenerate:${NC}"
    echo "  - 服务进程、systemd unit、journald 日志轮转配置"
    echo "  - config.json（UUID、Reality 密钥、shortId 全部换新）"
    echo "  - client-config.json、clash-verge.yaml"
    echo "  - run.sh、pid、日志、*.bak.* 备份"
    echo "  保留 manage.sh 本身；vless-server / keygen 会重新下载"
    echo ""

    if [ "$assume_yes" != 1 ]; then
        if [ -t 0 ]; then
            read -p "确认重建？/ Confirm rebuild? (y/N): " ans || ans="n"
            case "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" in
                y|yes) ;;
                *) echo "已取消 / Cancelled"; return 0 ;;
            esac
        else
            die "非交互环境请加 --yes 确认"
        fi
        echo ""
    fi

    # 先确保拿得到安装脚本，避免清干净了才发现没网络
    if ! installer=$(resolve_installer "$dir" "$custom"); then
        if [ -n "$custom" ]; then
            die "找不到指定的安装脚本: ${custom}（未做任何改动）"
        fi
        die "拿不到 install.sh（本地没有副本，下载也失败），未做任何改动"
    fi
    echo "安装脚本: ${installer}"
    echo ""

    ts=$(date +%Y%m%d-%H%M%S)

    echo -e "${YELLOW}[1/4] 备份现有配置 / Backing up...${NC}"
    backup_dir=$(backup_configs "$dir" "$ts") || backup_dir=""
    if [ -n "$backup_dir" ]; then
        ok "旧配置已备份: $backup_dir"
    else
        warn "没有可备份的配置（首次安装？）/ nothing to back up"
    fi
    echo ""

    echo -e "${YELLOW}[2/4] 停止服务 / Stopping...${NC}"
    if stop_all "$dir"; then
        ok "服务已停止，相关进程已退出"
    else
        warn "仍有进程残留，继续执行（安装脚本会再清理一次）"
    fi
    echo ""

    echo -e "${YELLOW}[3/4] 清理残留 / Cleaning...${NC}"
    clean_residue "$dir"
    ok "清理完成"
    echo ""

    echo -e "${YELLOW}[4/4] 重新安装 / Reinstalling...${NC}"
    echo "接下来交给 install.sh，会重新询问端口、伪装域名和部署方式"
    echo ""

    bash "$installer"
    rc=$?

    # 下载来的临时安装脚本用完就删；安装目录里的副本保留
    if [ -z "$custom" ] && [ "$installer" != "$dir/install.sh" ]; then
        rm -f "$installer"
        installer=""
    fi

    if [ "$rc" -ne 0 ]; then
        echo ""
        warn "install.sh 退出码 ${rc}，重建未完成 / rebuild failed"
        if [ -n "$backup_dir" ]; then
            echo "  用备份恢复原配置:"
            echo "    cp -p ${backup_dir}/config.json ${dir}/config.json"
        fi
        echo "  或者直接重新跑安装脚本:"
        echo "    bash <(curl -fsSL ${INSTALL_URL})"
        return "$rc"
    fi

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  重建完成 / Rebuild Complete${NC}"
    echo -e "${GREEN}=========================================${NC}"
    [ -n "$backup_dir" ] && echo "  旧配置备份: $backup_dir"
    echo ""
    echo "  新的客户端配置需要重新导入，或用下面命令导出:"
    echo "    bash $dir/manage.sh export --tar"
    echo ""

    if [ -f "$dir/config.json" ]; then
        show_config "$dir/config.json"
    fi
}

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------

CMD=""
ARGS=()
CONFIG=""
SYNC_CLIENTS=1
NO_RESTART=0
EXPORT_TAR=0
ASSUME_YES=0
INSTALLER=""

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
        --tar)
            EXPORT_TAR=1
            shift
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        --installer)
            [ $# -ge 2 ] || die "--installer 需要一个路径参数"
            INSTALLER="$2"
            shift 2
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

# 先校验命令本身，避免把「命令拼错」报成「找不到配置文件」
case "$CMD" in
    show|set-port|port|set-domain|domain|export|rebuild|reinstall) ;;
    *)
        die "未知命令 / unknown command: ${CMD}（可用: show, set-port, set-domain, export, rebuild）"
        ;;
esac

# 必填参数也在读配置之前校验
case "$CMD" in
    set-port|port)
        [ "${#ARGS[@]}" -ge 1 ] || die "用法: bash manage.sh set-port <端口>"
        ;;
    set-domain|domain)
        [ "${#ARGS[@]}" -ge 1 ] || die "用法: bash manage.sh set-domain <域名>"
        ;;
esac

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

# rebuild 要能在配置已损坏/缺失时救场，所以不强制要求 config.json 存在
case "$CMD" in
    rebuild|reinstall) ;;
    *)
        [ -f "$CONFIG" ] || die "找不到配置文件: ${CONFIG}（用 -c 指定，或设置 XRAY_LITE_CONFIG）"
        ;;
esac

case "$CMD" in
    show)
        show_config "$CONFIG"
        ;;
    set-port|port)
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
    set-domain|domain)
        cmd_set_domain "$CONFIG" "${ARGS[0]}" "$SYNC_CLIENTS" "$NO_RESTART"
        ;;
    export)
        cmd_export "$CONFIG" "${ARGS[0]:-}" "$EXPORT_TAR"
        ;;
    rebuild|reinstall)
        cmd_rebuild "$CONFIG" "$ASSUME_YES" "$INSTALLER"
        ;;
    *)
        die "未知命令 / unknown command: ${CMD}（可用: show, set-port, set-domain, export, rebuild）"
        ;;
esac
