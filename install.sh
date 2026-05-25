#!/usr/bin/env bash
# =============================================================================
#  Rust Light Proxy v3  ·  一键安装管理脚本
#  -----------------------------------------------------------------------------
#  · 自动识别 amd64 / arm64 / armv7 架构
#  · 自动从 GitHub Releases 下载二进制（也支持脚本同目录离线安装）
#  · systemd 服务 + 自动重启 + 资源沙箱
#  · 交互菜单 / 非交互 ACTION=xxx 双模式
#  · 协议：socks5 / socks5h / http / mixed
#  · 出站 profile：default / ipv4 / ipv6 / wireguard_kernel (Cloudflare WARP)
#  · 网口检测、出口绑定、日志大小限制、流量统计、客户端 URI 打印
#  · 适用：Debian / Ubuntu / CentOS / RHEL / Fedora / Alpine / Arch
# =============================================================================

set -o pipefail

# =============================================================================
# 颜色 & 输出
# =============================================================================
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RESET="$(tput sgr0)";  C_BOLD="$(tput bold)";   C_DIM="$(tput dim)"
  C_RED="$(tput setaf 1)"; C_GREEN="$(tput setaf 2)"; C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"; C_MAGENTA="$(tput setaf 5)"; C_CYAN="$(tput setaf 6)"
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""
fi

msg()  { printf '%s\n' "$*"; }
ok()   { printf '%s[✓]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
info() { printf '%s[+]%s %s\n' "$C_CYAN"   "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
hint() { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_RESET"; }

hr() {
  printf '%s' "$C_DIM"
  printf '%.0s─' $(seq 1 64)
  printf '%s\n' "$C_RESET"
}

banner() {
  clear 2>/dev/null || true
  cat <<EOF
${C_CYAN}${C_BOLD}
╔══════════════════════════════════════════════════════════════╗
║         Rust Light Proxy  v3  ·  一键安装管理脚本             ║
║   SOCKS5 / SOCKS5H / HTTP / Mixed  ·  WARP / WireGuard 出站  ║
╚══════════════════════════════════════════════════════════════╝${C_RESET}
EOF
}

# =============================================================================
# 全局变量（可被环境变量覆盖）
# =============================================================================
BIN_PATH="${BIN_PATH:-/usr/local/bin/rust-light-proxy}"
INSTALL_DIR="${INSTALL_DIR:-/opt/light_proxy}"
CONFIG_DIR="${CONFIG_DIR:-/etc/rust-light-proxy}"
INSTANCE_DIR="${INSTANCE_DIR:-${CONFIG_DIR}/instances}"
LOG_DIR="${LOG_DIR:-/var/log/rust-light-proxy}"

LOG_LIMIT_FILE="${CONFIG_DIR}/log-limit.conf"
DEFAULT_LOG_LIMIT_MB="${DEFAULT_LOG_LIMIT_MB:-500}"
LOGROTATE_FILE="/etc/logrotate.d/rust-light-proxy"
LOG_CRON_FILE="/etc/cron.d/rust-light-proxy-logrotate"

SERVICE_PREFIX="${SERVICE_PREFIX:-rust-light-proxy}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_PREFIX}@.service"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub Releases 下载源
GITHUB_REPO="${GITHUB_REPO:-judy-gotv/Rust-SOCKS5-HTTP}"
RELEASE_TAG="${RELEASE_TAG:-latest}"

# =============================================================================
# 通用工具
# =============================================================================
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "请使用 root 运行：sudo bash $0"
    exit 1
  fi
}
command_exists() { command -v "$1" >/dev/null 2>&1; }
require_systemd() {
  if ! command_exists systemctl; then
    err "系统未检测到 systemd，无法继续。"
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)             echo amd64 ;;
    aarch64|arm64)            echo arm64 ;;
    armv7l|armv7|armhf|armv6l) echo armv7 ;;
    *) err "不支持的架构：$(uname -m)"; exit 1 ;;
  esac
}

random_password() {
  if command_exists openssl; then
    openssl rand -base64 18 | tr -d '\n=+/' | cut -c1-20
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
  fi
}

random_port() {
  echo $(( (RANDOM % 50000) + 10000 ))
}

detect_public_ip() {
  local ip=""
  if command_exists curl; then
    ip="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
    [ -z "$ip" ] && ip="$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  elif command_exists wget; then
    ip="$(wget -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)"
  fi
  [ -z "$ip" ] && ip="<server_ip>"
  echo "$ip"
}

human_bytes() {
  local b="${1:-0}"
  if [ "$b" -lt 1024 ]; then echo "${b} B"
  elif [ "$b" -lt 1048576 ]; then awk -v b="$b" 'BEGIN{printf "%.2f KB", b/1024}'
  elif [ "$b" -lt 1073741824 ]; then awk -v b="$b" 'BEGIN{printf "%.2f MB", b/1048576}'
  elif [ "$b" -lt 1099511627776 ]; then awk -v b="$b" 'BEGIN{printf "%.2f GB", b/1073741824}'
  else awk -v b="$b" 'BEGIN{printf "%.2f TB", b/1099511627776}'
  fi
}

install_packages_if_needed() {
  if command_exists curl && command_exists ss; then return; fi
  if command_exists apt-get; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends ca-certificates curl iproute2 cron >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf install -y ca-certificates curl iproute cronie >/dev/null 2>&1 || true
  elif command_exists yum; then
    yum install -y ca-certificates curl iproute cronie >/dev/null 2>&1 || true
  elif command_exists apk; then
    apk add --no-cache ca-certificates curl iproute2 dcron >/dev/null 2>&1 || true
  elif command_exists pacman; then
    pacman -Sy --noconfirm ca-certificates curl iproute2 cronie >/dev/null 2>&1 || true
  fi
}

# =============================================================================
# 二进制下载与安装
# =============================================================================
download_file() {
  local url="$1" dst="$2"
  if command_exists curl; then
    curl -fSL --retry 3 --connect-timeout 10 -o "$dst" "$url"
  elif command_exists wget; then
    wget -O "$dst" "$url"
  else
    err "需要 curl 或 wget"; return 1
  fi
}

resolve_release_url() {
  local arch="$1" tag="$2"
  local asset="rust-light-proxy-linux-${arch}"
  if [ "$tag" = "latest" ]; then
    echo "https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
  else
    echo "https://github.com/${GITHUB_REPO}/releases/download/${tag}/${asset}"
  fi
}

install_binary() {
  if [ -x "$BIN_PATH" ]; then return 0; fi

  local arch; arch="$(detect_arch)"
  info "本机架构：${C_BOLD}${arch}${C_RESET}"

  # 1) 优先使用脚本同目录的二进制（离线场景）
  local candidates=(
    "${SCRIPT_DIR}/rust-light-proxy-linux-${arch}"
    "${SCRIPT_DIR}/rust-light-proxy"
    "./rust-light-proxy-linux-${arch}"
    "./rust-light-proxy"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      info "使用本地二进制：${c}"
      install -m 0755 "$c" "$BIN_PATH"
      ok "已安装到：${BIN_PATH}"
      return 0
    fi
  done

  # 2) 从 GitHub Releases 下载
  local url tmp; url="$(resolve_release_url "$arch" "$RELEASE_TAG")"; tmp="$(mktemp)"
  info "从 GitHub Releases 下载：${url}"
  if ! download_file "$url" "$tmp"; then
    err "下载失败。"
    hint "URL: ${url}"
    hint "你也可以把二进制放到脚本同目录后再运行。"
    rm -f "$tmp"; exit 1
  fi
  if [ ! -s "$tmp" ]; then err "下载文件为空"; rm -f "$tmp"; exit 1; fi
  if ! head -c 4 "$tmp" | grep -q $'\x7fELF'; then
    err "下载的文件不是有效的 ELF 二进制（可能是 404 HTML 页面）"
    hint "URL: ${url}"
    rm -f "$tmp"; exit 1
  fi
  install -m 0755 "$tmp" "$BIN_PATH"
  rm -f "$tmp"
  ok "已安装到：${BIN_PATH}"
}

cmd_update() {
  local arch; arch="$(detect_arch)"
  local url tmp; url="$(resolve_release_url "$arch" "$RELEASE_TAG")"; tmp="$(mktemp)"
  info "下载最新版本：${url}"
  if ! download_file "$url" "$tmp"; then
    err "下载失败"; rm -f "$tmp"; return 1
  fi
  if ! head -c 4 "$tmp" | grep -q $'\x7fELF'; then
    err "下载文件不是 ELF 二进制"; rm -f "$tmp"; return 1
  fi
  install -m 0755 "$tmp" "$BIN_PATH"; rm -f "$tmp"
  ok "已更新：$($BIN_PATH --version 2>/dev/null | head -n1)"

  local names; names="$(list_instances)"
  if [ -n "$names" ]; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      systemctl restart "${SERVICE_PREFIX}@${name}.service" >/dev/null 2>&1 || true
      info "已重启实例：$name"
    done <<< "$names"
  fi
}

# =============================================================================
# systemd 模板服务
# =============================================================================
write_template_service() {
  if [ -f "$SERVICE_FILE" ]; then return; fi
  mkdir -p "$LOG_DIR" "$INSTANCE_DIR"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Rust Light Proxy (%i)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/sh -c '${BIN_PATH} -c ${INSTANCE_DIR}/%i.toml >> ${LOG_DIR}/%i.log 2>&1'
Restart=on-failure
RestartSec=2s
LimitNOFILE=1048576

# 允许绑定指定网口 / <1024 端口；CAP_NET_ADMIN 用于 v3 wireguard_kernel 出站
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_NET_ADMIN

NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
ReadWritePaths=${LOG_DIR}
ReadOnlyPaths=${BIN_PATH} ${INSTANCE_DIR}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

# =============================================================================
# 实例列表 / 读写配置
# =============================================================================
list_instances() {
  [ -d "$INSTANCE_DIR" ] || return
  find "$INSTANCE_DIR" -maxdepth 1 -type f -name '*.toml' -printf '%f\n' 2>/dev/null \
    | sed 's/\.toml$//' | sort
}

instance_exists() {
  [ -f "${INSTANCE_DIR}/$1.toml" ]
}

write_instance_config() {
  local name="$1" mode="$2" listen_addr="$3" port="$4"
  local user="$5" pass="$6" max_conn="$7" bind="${8:-}"
  local outbound_profile="${9:-default}"
  # WireGuard / WARP 参数（仅 outbound_profile=warp 时使用，从环境变量读取）
  local wg_iface="${WG_INTERFACE:-warp0}"
  local wg_mark="${WG_MARK:-1001}"
  local wg_table="${WG_TABLE:-1001}"
  local wg_priority="${WG_PRIORITY:-11001}"
  local wg_privkey="${WG_PRIVATE_KEY:-}"
  local wg_addr4="${WG_ADDR4:-172.16.0.2/32}"
  local wg_addr6="${WG_ADDR6:-}"
  local wg_mtu="${WG_MTU:-1280}"
  local wg_peer_pub="${WG_PEER_PUBLIC_KEY:-}"
  local wg_endpoint="${WG_ENDPOINT:-engage.cloudflareclient.com:2408}"
  local wg_allowed_ips="${WG_ALLOWED_IPS:-0.0.0.0/0, ::/0}"
  local wg_keepalive="${WG_KEEPALIVE:-25}"

  mkdir -p "$INSTANCE_DIR"
  chmod 0755 "$CONFIG_DIR" "$INSTANCE_DIR"

  # v3 协议拆分：socks5 / socks5h / http / mixed
  local http_enabled="false"
  local socks_enabled="true"
  local remote_dns="false"
  local legacy_mode="$mode"
  case "$mode" in
    socks5)  http_enabled="false"; socks_enabled="true"; remote_dns="false"; legacy_mode="socks5" ;;
    socks5h) http_enabled="false"; socks_enabled="true"; remote_dns="true";  legacy_mode="socks5" ;;
    http)    http_enabled="true";  socks_enabled="false"; legacy_mode="http" ;;
    mixed)   http_enabled="true";  socks_enabled="true";  remote_dns="true"; legacy_mode="mixed" ;;
  esac

  local auth_enabled="true"
  if [ -z "$user" ] || [ -z "$pass" ]; then auth_enabled="false"; fi

  # 构造 [[outbounds]] 与 [[listeners]] 块
  local outbounds_block=""
  local listener_outbound="default"
  case "$outbound_profile" in
    ipv4) listener_outbound="ipv4" ;;
    ipv6) listener_outbound="ipv6" ;;
    warp) listener_outbound="warp" ;;
    *)    listener_outbound="default" ;;
  esac

  outbounds_block=$'[[outbounds]]\nname = "default"\ntype = "default"\n\n[[outbounds]]\nname = "ipv4"\ntype = "ipv4"\n\n[[outbounds]]\nname = "ipv6"\ntype = "ipv6"\n'

  if [ "$outbound_profile" = "warp" ]; then
    local addrs_line="\"${wg_addr4}\""
    [ -n "$wg_addr6" ] && addrs_line="\"${wg_addr4}\", \"${wg_addr6}\""
    # allowed_ips: split by comma
    local allowed_ips_toml=""
    local _aip
    IFS=',' read -ra _aip_arr <<< "$wg_allowed_ips"
    for _aip in "${_aip_arr[@]}"; do
      _aip="${_aip# }"; _aip="${_aip% }"
      [ -z "$_aip" ] && continue
      [ -n "$allowed_ips_toml" ] && allowed_ips_toml+=", "
      allowed_ips_toml+="\"${_aip}\""
    done

    outbounds_block+=$'\n[[outbounds]]\nname = "warp"\ntype = "wireguard_kernel"\n'
    outbounds_block+="interface = \"${wg_iface}\""$'\n'
    outbounds_block+="mark = ${wg_mark}"$'\n'
    outbounds_block+=$'bind_interface = true\n\n'
    outbounds_block+=$'[outbounds.wireguard]\nmanage = true\ncreate_interface = true\nsetup_routes = true\n'
    outbounds_block+="private_key = \"${wg_privkey}\""$'\n'
    outbounds_block+="addresses = [${addrs_line}]"$'\n'
    outbounds_block+=$'listen_port = 0\n'
    outbounds_block+="mtu = ${wg_mtu}"$'\n'
    outbounds_block+="peer_public_key = \"${wg_peer_pub}\""$'\n'
    outbounds_block+="endpoint = \"${wg_endpoint}\""$'\n'
    outbounds_block+="allowed_ips = [${allowed_ips_toml}]"$'\n'
    outbounds_block+="persistent_keepalive_secs = ${wg_keepalive}"$'\n'
    outbounds_block+="route_table = ${wg_table}"$'\n'
    outbounds_block+="route_priority = ${wg_priority}"$'\n'
  fi

  # listeners：mixed 模式同时挂 socks5h + http；其余单 listener
  local listeners_block=""
  if [ "$mode" = "mixed" ]; then
    listeners_block+=$'[[listeners]]\n'
    listeners_block+="name = \"${name}-socks5h\""$'\n'
    listeners_block+="listen = \"${listen_addr}:${port}\""$'\n'
    listeners_block+=$'protocol = "socks5h"\n'
    listeners_block+="outbound = \"${listener_outbound}\""$'\n'
    # mixed = 同端口自动识别，不要双 listener，由 server.mode = mixed 触发自动识别
    listeners_block=""
  else
    listeners_block+=$'[[listeners]]\n'
    listeners_block+="name = \"${name}-${mode}\""$'\n'
    listeners_block+="listen = \"${listen_addr}:${port}\""$'\n'
    listeners_block+="protocol = \"${mode}\""$'\n'
    listeners_block+="outbound = \"${listener_outbound}\""$'\n'
  fi

  cat > "${INSTANCE_DIR}/${name}.toml" <<EOF
# rust-light-proxy v3 实例：${name}
# protocol=${mode}  outbound=${outbound_profile}
[server]
listen = "${listen_addr}:${port}"
mode = "${legacy_mode}"

# 最大并发连接（硬上限）；0 表示采用安全默认 512
max_connections = ${max_conn}
memory_limit_mb = 512
connect_timeout_secs = 4
idle_timeout_secs = 120
handshake_timeout_secs = 2
shutdown_grace_secs = 15
max_pending_connects = 128

# 旧单监听模式的出站绑定（保留兼容；多 outbound 模式以 [[outbounds]] 为准）
outbound_bind = "${bind}"
expose_bind_addr = false

${outbounds_block}
${listeners_block}
[auth]
enabled = ${auth_enabled}
username = "${user}"
password = "${pass}"

[socks5]
enabled = ${socks_enabled}
remote_dns = ${remote_dns}

[http]
enabled = ${http_enabled}
max_header_bytes = 8192

[dns]
prefer_ipv4 = true
cache_enabled = true
cache_ttl_secs = 300
cache_capacity = 4096
timeout_secs = 2
negative_ttl_secs = 10
max_inflight = 64

[logging]
level = "warn"
access_log = true
json = false
hash_target = false

[metrics]
enabled = false
listen = "127.0.0.1:9090"
allow_cidr = ["127.0.0.0/8", "::1/128"]

[runtime]
worker_threads = 0
max_blocking_threads = 2

[tuning]
so_rcvbuf = 0
so_sndbuf = 0
tcp_nodelay = false
tcp_keepalive = true
keepalive_idle_secs = 60
tcp_fastopen = false
tcp_quickack = false
reuse_port = false
listen_backlog = 1024
use_splice = false
relay_buf_bytes = 131072
buffer_pool_bytes = 8388608

[security]
per_ip_rate_per_sec = 20
per_ip_burst = 40
auth_fail_max = 10
auth_ban_secs = 300
handshake_min_bytes = 16
max_active_per_ip = 64
max_pending_dns_per_ip = 16
max_pending_connect_per_ip = 32
EOF
  chmod 0600 "${INSTANCE_DIR}/${name}.toml"
}

# =============================================================================
# 日志大小限制
# =============================================================================
get_log_limit_mb() {
  [ -f "$LOG_LIMIT_FILE" ] && cat "$LOG_LIMIT_FILE" || echo "$DEFAULT_LOG_LIMIT_MB"
}

set_log_limit_mb() {
  mkdir -p "$CONFIG_DIR"
  echo "$1" > "$LOG_LIMIT_FILE"
  chmod 0644 "$LOG_LIMIT_FILE"
}

apply_log_limit() {
  local limit_mb; limit_mb="$(get_log_limit_mb)"
  if ! [[ "$limit_mb" =~ ^[0-9]+$ ]] || [ "$limit_mb" -le 0 ]; then
    limit_mb="$DEFAULT_LOG_LIMIT_MB"; set_log_limit_mb "$limit_mb"
  fi
  mkdir -p "$LOG_DIR"; chmod 0755 "$LOG_DIR"

  if command_exists logrotate; then
    cat > "$LOGROTATE_FILE" <<EOF
${LOG_DIR}/*.log {
    size ${limit_mb}M
    rotate 0
    missingok
    notifempty
    copytruncate
    nocompress
}
EOF
    chmod 0644 "$LOGROTATE_FILE"
  fi

  cat > "$LOG_CRON_FILE" <<EOF
# rust-light-proxy 日志强制大小限制（${limit_mb} MB），每分钟检查
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
* * * * * root limit_bytes=\$((${limit_mb} * 1024 * 1024)); for f in ${LOG_DIR}/*.log; do [ -f "\$f" ] || continue; sz=\$(stat -c %s "\$f" 2>/dev/null || echo 0); if [ "\$sz" -gt "\$limit_bytes" ]; then : > "\$f"; fi; done
EOF
  chmod 0644 "$LOG_CRON_FILE"

  systemctl reload cron       >/dev/null 2>&1 || \
    systemctl reload crond    >/dev/null 2>&1 || \
    systemctl restart cron    >/dev/null 2>&1 || \
    systemctl restart crond   >/dev/null 2>&1 || true
}

enforce_log_now() {
  local limit_mb limit_bytes; limit_mb="$(get_log_limit_mb)"
  limit_bytes=$(( limit_mb * 1024 * 1024 ))
  [ -d "$LOG_DIR" ] || return 0
  shopt -s nullglob
  for f in "$LOG_DIR"/*.log; do
    [ -f "$f" ] || continue
    local sz; sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if [ "$sz" -gt "$limit_bytes" ]; then : > "$f"; fi
  done
  shopt -u nullglob
}

cmd_log_limit() {
  local current; current="$(get_log_limit_mb)"
  msg ""
  msg "${C_BOLD}日志大小限制${C_RESET}"
  msg "  当前上限：${C_CYAN}${current} MB${C_RESET}"
  msg "  默认上限：${C_DIM}${DEFAULT_LOG_LIMIT_MB} MB${C_RESET}"
  msg "  说明：${C_DIM}单个实例日志文件超过该值即被清空（truncate）重新计数${C_RESET}"
  msg ""
  read -rp "请输入新的上限（MB），回车 = 保持，0/d = 恢复默认 ${DEFAULT_LOG_LIMIT_MB}MB: " input
  local new_mb
  if   [ -z "$input" ]; then new_mb="$current"
  elif [ "$input" = "0" ] || [ "$input" = "d" ] || [ "$input" = "D" ]; then new_mb="$DEFAULT_LOG_LIMIT_MB"
  else
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then err "请输入正整数（MB）"; return; fi
    new_mb="$input"
  fi
  set_log_limit_mb "$new_mb"; apply_log_limit; enforce_log_now
  ok "日志大小上限已设置为：${new_mb} MB"
}

# =============================================================================
# 网口检测
# =============================================================================
list_interfaces() {
  if command_exists ip; then
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | while read -r ifname; do
      [ -z "$ifname" ] || [ "$ifname" = "lo" ] && continue
      local state ipv4 ipv6
      state="$(cat /sys/class/net/${ifname}/operstate 2>/dev/null || echo unknown)"
      ipv4="$(ip -4 -o addr show dev "$ifname" 2>/dev/null | awk '{print $4}' | head -n1 | cut -d/ -f1)"
      ipv6="$(ip -6 -o addr show dev "$ifname" 2>/dev/null | awk '$4 !~ /^fe80/ {print $4}' | head -n1 | cut -d/ -f1)"
      printf '%s|%s|%s|%s\n' "$ifname" "$state" "${ipv4:--}" "${ipv6:--}"
    done
  else
    for d in /sys/class/net/*; do
      [ -d "$d" ] || continue
      local n; n="$(basename "$d")"
      [ "$n" = "lo" ] && continue
      printf '%s|%s|%s|%s\n' "$n" "$(cat $d/operstate 2>/dev/null || echo unknown)" "-" "-"
    done
  fi
}

pick_interface() {
  # 输出走 /dev/tty，结果走 stdout
  local lines; lines="$(list_interfaces)"
  if [ -z "$lines" ]; then warn "未检测到任何网口" >/dev/tty; echo ""; return; fi

  {
    msg ""
    msg "${C_BOLD}出口绑定（指定走哪个网口 / IP 出网）${C_RESET}"
    msg "${C_DIM}  本机检测到的网口：${C_RESET}"
    hr
    printf "  ${C_BOLD}%-4s %-14s %-8s %-18s %s${C_RESET}\n" "#" "网口名" "状态" "IPv4" "IPv6"
    hr
  } >/dev/tty

  local i=0
  local arr=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local ifname state ipv4 ipv6 color
    ifname="$(echo "$line" | cut -d'|' -f1)"
    state="$(echo  "$line" | cut -d'|' -f2)"
    ipv4="$(echo   "$line" | cut -d'|' -f3)"
    ipv6="$(echo   "$line" | cut -d'|' -f4)"
    if [ "$state" = "up" ] || [ "$state" = "unknown" ]; then color="$C_GREEN"; else color="$C_RED"; fi
    i=$((i+1)); arr+=("$ifname")
    printf "  ${C_CYAN}%-4s${C_RESET} %-14s ${color}%-8s${C_RESET} %-18s %s\n" "$i)" "$ifname" "$state" "$ipv4" "$ipv6" >/dev/tty
  done <<< "$lines"

  {
    hr
    printf "  ${C_CYAN}%-4s${C_RESET} %s\n" "0)" "默认（不绑定，使用系统路由）${C_GREEN} ← 推荐${C_RESET}"
    printf "  ${C_CYAN}%-4s${C_RESET} %s\n" "c)" "手动输入网口名或源 IP"
    msg ""
  } >/dev/tty

  local sel; read -rp "请选择 [0-${i} / c，默认 0]: " sel </dev/tty
  sel="${sel:-0}"
  case "$sel" in
    0|"") echo ""; return ;;
    c|C)
      local custom; read -rp "请输入网口名（eth0 / ens18 / wlan0）或源 IP（1.2.3.4）: " custom </dev/tty
      echo "${custom// /}"; return ;;
    *)
      if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$i" ]; then
        echo "${arr[$((sel-1))]}"; return
      fi
      warn "无效选择，使用默认（不绑定）" >/dev/tty; echo "" ;;
  esac
}

# =============================================================================
# 实例选择
# =============================================================================
pick_instance() {
  local prompt="${1:-请选择实例}"
  local names; names="$(list_instances)"
  if [ -z "$names" ]; then warn "暂无实例" >/dev/tty; return 1; fi
  { msg ""; msg "${C_BOLD}${prompt}${C_RESET}"; } >/dev/tty
  local i=0; local arr=()
  while IFS= read -r n; do
    i=$((i+1)); arr+=("$n")
    printf "  ${C_CYAN}%2d)${C_RESET} %s\n" "$i" "$n" >/dev/tty
  done <<< "$names"
  printf "  ${C_CYAN}%2d)${C_RESET} 全部\n" "$((i+1))" >/dev/tty
  local sel; read -rp "请选择 [1-$((i+1))]: " sel </dev/tty
  if [ "$sel" = "$((i+1))" ]; then printf '%s\n' "${arr[@]}"; return 0; fi
  if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$i" ]; then
    echo "${arr[$((sel-1))]}"; return 0
  fi
  err "选择无效" >/dev/tty; return 1
}

# =============================================================================
# 客户端连接信息打印
# =============================================================================
print_client_info() {
  local proxy_type="$1" ip="$2" port="$3" user="$4" pass="$5"
  local auth_part=""
  if [ -n "$user" ] && [ -n "$pass" ]; then auth_part="${user}:${pass}@"; fi

  hr
  msg "${C_BOLD}${C_CYAN}📡 客户端连接信息${C_RESET}"
  hr

  case "$proxy_type" in
    socks5)
      msg "${C_BOLD}SOCKS5 模式${C_DIM}（客户端本地解析 DNS，不接受域名目标）${C_RESET}"
      msg "  ${C_GREEN}socks5://${auth_part}${ip}:${port}${C_RESET}"
      msg ""
      ;;
    socks5h)
      msg "${C_BOLD}SOCKS5H 模式${C_DIM}（推荐 · DNS 在代理端解析，配合 ipv4/ipv6/WARP 出站）${C_RESET}"
      msg "  ${C_GREEN}socks5h://${auth_part}${ip}:${port}${C_RESET}"
      msg ""
      ;;
    http)
      msg "${C_BOLD}HTTP CONNECT 模式${C_DIM}（域名由代理解析）${C_RESET}"
      msg "  ${C_GREEN}http://${auth_part}${ip}:${port}${C_RESET}"
      msg ""
      ;;
    mixed)
      msg "${C_BOLD}Mixed 模式${C_DIM}（同端口自动识别）${C_RESET}"
      msg "  ${C_GREEN}socks5h://${auth_part}${ip}:${port}${C_RESET}   ${C_DIM}# SOCKS5（远程 DNS）${C_RESET}"
      msg "  ${C_GREEN}socks5://${auth_part}${ip}:${port}${C_RESET}    ${C_DIM}# SOCKS5（本地 DNS）${C_RESET}"
      msg "  ${C_GREEN}http://${auth_part}${ip}:${port}${C_RESET}      ${C_DIM}# HTTP CONNECT${C_RESET}"
      msg ""
      ;;
  esac

  msg "${C_BOLD}分字段格式${C_RESET}"
  printf "  ${C_DIM}%-10s${C_RESET} %s\n" "Host:" "$ip"
  printf "  ${C_DIM}%-10s${C_RESET} %s\n" "Port:" "$port"
  printf "  ${C_DIM}%-10s${C_RESET} %s\n" "Type:" "$proxy_type"
  if [ -n "$user" ]; then
    printf "  ${C_DIM}%-10s${C_RESET} %s\n" "User:" "$user"
    printf "  ${C_DIM}%-10s${C_RESET} %s\n" "Pass:" "$pass"
  else
    printf "  ${C_DIM}%-10s${C_RESET} %s\n" "Auth:" "无"
  fi
  msg ""

  msg "${C_BOLD}快速测试${C_RESET}"
  case "$proxy_type" in
    socks5)
      msg "  ${C_DIM}# 查看出口 IP（本地 DNS）${C_RESET}"
      msg "  curl -x socks5://${auth_part}${ip}:${port} https://api.ipify.org" ;;
    socks5h|mixed)
      msg "  ${C_DIM}# 查看出口 IP（远程 DNS）${C_RESET}"
      msg "  curl -x socks5h://${auth_part}${ip}:${port} https://api.ipify.org" ;;
  esac
  if [ "$proxy_type" = "http" ] || [ "$proxy_type" = "mixed" ]; then
    msg "  ${C_DIM}# 查看出口 IP（HTTP CONNECT）${C_RESET}"
    msg "  curl -x http://${auth_part}${ip}:${port} https://api.ipify.org"
  fi
  hr
}

# =============================================================================
# cmd_add - 添加实例
# =============================================================================
cmd_add() {
  local proxy_type="${PROXY_TYPE:-}"
  local name="${INSTANCE_NAME:-}"
  local listen_addr="${LISTEN_ADDR:-0.0.0.0}"
  local port="${LISTEN_PORT:-}"
  local user="${PROXY_USER:-}"
  local pass="${PROXY_PASS:-}"
  local max_conn="${MAX_CONNECTIONS:-0}"
  local outbound_profile="${OUTBOUND_PROFILE:-}"

  if [ -z "$proxy_type" ]; then
    msg ""
    msg "${C_BOLD}选择代理协议${C_RESET}"
    msg "  ${C_CYAN}1)${C_RESET} SOCKS5    ${C_DIM}(客户端必须传 IP，代理不接受域名目标)${C_RESET}"
    msg "  ${C_CYAN}2)${C_RESET} SOCKS5H   ${C_DIM}(推荐 · 域名在代理端解析，配合 ipv4/ipv6/WARP)${C_RESET}"
    msg "  ${C_CYAN}3)${C_RESET} HTTP      ${C_DIM}(HTTP CONNECT，域名由代理解析)${C_RESET}"
    msg "  ${C_CYAN}4)${C_RESET} Mixed     ${C_DIM}(单端口自动识别 SOCKS5 或 HTTP)${C_RESET}"
    read -rp "请选择 [1-4，默认 2]: " sel
    case "${sel:-2}" in
      1) proxy_type=socks5 ;;
      2) proxy_type=socks5h ;;
      3) proxy_type=http ;;
      4) proxy_type=mixed ;;
      *) proxy_type=socks5h ;;
    esac
  fi
  case "$proxy_type" in socks5|socks5h|http|mixed) ;; *) err "未知 PROXY_TYPE：$proxy_type"; exit 1 ;; esac

  if [ -z "$name" ]; then
    local default_name idx=1
    while :; do default_name="${proxy_type}-${idx}"; instance_exists "$default_name" || break; idx=$((idx+1)); done
    read -rp "实例名称 [${default_name}]: " name; name="${name:-$default_name}"
  fi
  if [[ ! "$name" =~ ^[A-Za-z0-9_.\-]+$ ]]; then err "实例名只允许 字母/数字/_/./-"; exit 1; fi
  if instance_exists "$name"; then err "实例已存在：$name"; exit 1; fi

  if [ -z "$port" ]; then
    local default_port; default_port="$(random_port)"
    read -rp "监听端口 [${default_port}]: " port; port="${port:-$default_port}"
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then err "端口非法：$port"; exit 1; fi

  if [ -z "$user" ]; then read -rp "代理账号 [user]: " user; user="${user:-user}"; fi
  if [ -z "$pass" ]; then
    local default_pass; default_pass="$(random_password)"
    read -rp "代理密码 [回车随机: ${default_pass}]: " pass; pass="${pass:-$default_pass}"
  fi

  if [ -z "$max_conn" ]; then max_conn=0; fi
  if ! [[ "$max_conn" =~ ^[0-9]+$ ]]; then err "最大并发非法：$max_conn"; exit 1; fi

  # 出站 profile 选择（v3 新增）
  if [ -z "$outbound_profile" ] && [ -t 0 ]; then
    msg ""
    msg "${C_BOLD}选择出站 profile（决定连接走哪条出口路径）${C_RESET}"
    msg "  ${C_CYAN}1)${C_RESET} default ${C_DIM}(系统默认路由)${C_RESET}"
    msg "  ${C_CYAN}2)${C_RESET} ipv4    ${C_DIM}(只解析 / 连接 IPv4)${C_RESET}"
    msg "  ${C_CYAN}3)${C_RESET} ipv6    ${C_DIM}(只解析 / 连接 IPv6)${C_RESET}"
    msg "  ${C_CYAN}4)${C_RESET} warp    ${C_DIM}(Cloudflare WARP / kernel WireGuard 出口)${C_RESET}"
    read -rp "请选择 [1-4，默认 1]: " psel
    case "${psel:-1}" in
      1) outbound_profile=default ;;
      2) outbound_profile=ipv4 ;;
      3) outbound_profile=ipv6 ;;
      4) outbound_profile=warp ;;
      *) outbound_profile=default ;;
    esac
  fi
  [ -z "$outbound_profile" ] && outbound_profile="default"
  case "$outbound_profile" in default|ipv4|ipv6|warp) ;; *) err "未知 OUTBOUND_PROFILE：$outbound_profile"; exit 1 ;; esac

  # 仅 default profile 允许网口/源 IP 绑定（其他 profile 已指定语义）
  local bind="${OUTBOUND_BIND:-}"
  if [ "$outbound_profile" = "default" ] && [ -z "$bind" ] && [ -t 0 ]; then
    bind="$(pick_interface)"
  fi

  # warp profile：检查 WireGuard 凭据
  if [ "$outbound_profile" = "warp" ]; then
    if [ -z "${WG_PRIVATE_KEY:-}" ] || [ -z "${WG_PEER_PUBLIC_KEY:-}" ]; then
      if [ -t 0 ]; then
        msg ""
        warn "warp 出站需要 WireGuard 凭据，请粘贴 Cloudflare WARP 注册结果："
        [ -z "${WG_PRIVATE_KEY:-}" ]    && read -rp "  WG_PRIVATE_KEY    (你的 private key): " WG_PRIVATE_KEY
        [ -z "${WG_PEER_PUBLIC_KEY:-}" ] && read -rp "  WG_PEER_PUBLIC_KEY (peer public key): " WG_PEER_PUBLIC_KEY
        [ -z "${WG_ADDR4:-}" ]          && read -rp "  WG_ADDR4          [172.16.0.2/32]: " WG_ADDR4
        [ -z "${WG_ENDPOINT:-}" ]       && read -rp "  WG_ENDPOINT       [engage.cloudflareclient.com:2408]: " WG_ENDPOINT
        export WG_PRIVATE_KEY WG_PEER_PUBLIC_KEY WG_ADDR4 WG_ENDPOINT
      else
        err "warp 出站需要 WG_PRIVATE_KEY 与 WG_PEER_PUBLIC_KEY 环境变量"; exit 1
      fi
    fi
    if [ -z "$WG_PRIVATE_KEY" ] || [ -z "$WG_PEER_PUBLIC_KEY" ]; then
      err "WireGuard 凭据缺失，已取消"; exit 1
    fi
  fi

  install_binary
  write_template_service
  if [ -n "${LOG_LIMIT_MB:-}" ] && [[ "$LOG_LIMIT_MB" =~ ^[0-9]+$ ]] && [ "$LOG_LIMIT_MB" -gt 0 ]; then
    set_log_limit_mb "$LOG_LIMIT_MB"
  fi
  [ ! -f "$LOG_LIMIT_FILE" ] && set_log_limit_mb "$DEFAULT_LOG_LIMIT_MB"
  apply_log_limit
  write_instance_config "$name" "$proxy_type" "$listen_addr" "$port" "$user" "$pass" "$max_conn" "$bind" "$outbound_profile"

  local svc="${SERVICE_PREFIX}@${name}.service"
  systemctl daemon-reload
  systemctl enable --now "$svc" >/dev/null 2>&1 || systemctl restart "$svc"

  sleep 1
  if systemctl is-active --quiet "$svc"; then
    ok "实例已启动：$svc"
  else
    warn "实例启动失败，请查看：journalctl -u $svc -n 50"
    hint "或：tail -n 50 ${LOG_DIR}/${name}.log"
  fi

  local ip; ip="$(detect_public_ip)"

  hr
  msg "${C_BOLD}${C_GREEN}✔ 实例已就绪${C_RESET}"
  hr
  printf "  %-14s %s\n" "名称"     "$name"
  printf "  %-14s %s\n" "协议"     "$proxy_type"
  printf "  %-14s %s\n" "监听"     "${listen_addr}:${port}"
  printf "  %-14s %s\n" "账号"     "$user"
  printf "  %-14s %s\n" "密码"     "$pass"
  printf "  %-14s %s\n" "最大并发" "$( [ "$max_conn" = "0" ] && echo "默认 512" || echo "$max_conn" )"
  printf "  %-14s %s\n" "出站 profile" "$outbound_profile"
  printf "  %-14s %s\n" "出口绑定" "$( [ -z "$bind" ] && echo "默认路由" || echo "$bind" )"
  printf "  %-14s %s\n" "服务"     "$svc"
  printf "  %-14s %s\n" "配置"     "${INSTANCE_DIR}/${name}.toml"
  printf "  %-14s %s\n" "日志"     "${LOG_DIR}/${name}.log"

  print_client_info "$proxy_type" "$ip" "$port" "$user" "$pass"
}

# =============================================================================
# 实例配置解析（兼容 v3 [[listeners]] / [[outbounds]] 与旧 [server].mode）
# =============================================================================
parse_instance_protocol() {
  local cfg="$1"
  local proto; proto="$(grep -E '^[[:space:]]*protocol[[:space:]]*=' "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
  if [ -n "$proto" ]; then echo "$proto"; return; fi
  grep -E '^mode' "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/'
}
parse_instance_outbound() {
  local cfg="$1"
  local ob; ob="$(grep -E '^[[:space:]]*outbound[[:space:]]*=' "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
  echo "${ob:-default}"
}

# =============================================================================
# cmd_list / cmd_show / cmd_traffic / cmd_action / cmd_remove
# =============================================================================
cmd_list() {
  local names; names="$(list_instances)"
  if [ -z "$names" ]; then warn "暂无实例。可使用「添加实例」创建。"; return; fi
  hr
  printf "${C_BOLD}%-18s %-8s %-22s %-10s %-10s %s${C_RESET}\n" "名称" "协议" "监听" "状态" "出站" "服务"
  hr
  while IFS= read -r name; do
    local cfg="${INSTANCE_DIR}/${name}.toml"
    local mode listen status svc color outbound
    mode="$(parse_instance_protocol "$cfg")"
    listen="$(grep -E '^listen'      "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    outbound="$(parse_instance_outbound "$cfg")"
    svc="${SERVICE_PREFIX}@${name}.service"
    if systemctl is-active --quiet "$svc"; then status="running"; color="$C_GREEN"
    else status="stopped"; color="$C_RED"; fi
    printf "%-18s %-8s %-22s ${color}%-10s${C_RESET} %-10s %s\n" "$name" "$mode" "$listen" "$status" "$outbound" "$svc"
  done <<< "$names"
  hr
}

cmd_show() {
  local target="${INSTANCE_NAME:-}"
  local names
  if [ -n "$target" ]; then names="$target"
  else names="$(pick_instance "选择要查看的实例")" || return; fi

  local ip; ip="$(detect_public_ip)"
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    local cfg="${INSTANCE_DIR}/${name}.toml"
    [ -f "$cfg" ] || { err "实例不存在：$name"; continue; }
    local mode listen port user pass bind outbound
    mode="$(parse_instance_protocol "$cfg")"
    listen="$(grep -E '^listen'        "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    user="$(grep -E   '^username'      "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    pass="$(grep -E   '^password'      "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    bind="$(grep -E   '^outbound_bind' "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    outbound="$(parse_instance_outbound "$cfg")"
    port="${listen##*:}"

    hr
    msg "${C_BOLD}${C_GREEN}实例：${name}${C_RESET}"
    printf "  %-14s %s\n" "协议"     "$mode"
    printf "  %-14s %s\n" "监听"     "$listen"
    printf "  %-14s %s\n" "出站 profile" "$outbound"
    printf "  %-14s %s\n" "出口绑定" "$( [ -z "$bind" ] && echo "默认路由" || echo "$bind" )"

    print_client_info "$mode" "$ip" "$port" "$user" "$pass"
  done <<< "$names"
}

cmd_traffic() {
  local names; names="$(list_instances)"
  if [ -z "$names" ]; then warn "暂无实例"; return; fi
  hr
  printf "${C_BOLD}%-18s %-12s %-12s %-8s %-10s${C_RESET}\n" "名称" "上传" "下载" "连接数" "日志大小"
  hr
  while IFS= read -r name; do
    local svc="${SERVICE_PREFIX}@${name}.service"
    local logfile="${LOG_DIR}/${name}.log"
    local source_cmd
    if [ -f "$logfile" ]; then source_cmd="cat \"$logfile\""
    else source_cmd="journalctl -u \"$svc\" --no-pager -o cat 2>/dev/null"; fi
    local stats
    stats="$(eval "$source_cmd" | awk '
        {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^uploaded=/        || $i ~ /^upload_bytes=/   || $i ~ /^uploaded_bytes=/)   { split($i,a,"="); up+=a[2]+0 }
            if ($i ~ /^downloaded=/      || $i ~ /^download_bytes=/ || $i ~ /^downloaded_bytes=/) { split($i,a,"="); dn+=a[2]+0 }
            if ($i ~ /^status=/) conn += 1
          }
        }
        END { printf "%d %d %d", up+0, dn+0, conn+0 }')"
    local up dn conn size_h
    up="$(echo  "$stats" | awk '{print $1}')"
    dn="$(echo  "$stats" | awk '{print $2}')"
    conn="$(echo "$stats" | awk '{print $3}')"
    if [ -f "$logfile" ]; then
      size_h="$(human_bytes "$(stat -c %s "$logfile" 2>/dev/null || echo 0)")"
    else size_h="-"; fi
    printf "%-18s %-12s %-12s %-8s %-10s\n" "$name" "$(human_bytes "$up")" "$(human_bytes "$dn")" "$conn" "$size_h"
  done <<< "$names"
  hr
  hint "日志大小上限：$(get_log_limit_mb) MB（超过自动清空，统计将重置）"
}

cmd_action() {
  local action="$1"
  local target="${INSTANCE_NAME:-}"
  local names
  if [ -n "$target" ]; then names="$target"
  else names="$(pick_instance "选择要 ${action} 的实例")" || return; fi
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    local svc="${SERVICE_PREFIX}@${name}.service"
    case "$action" in
      start)   systemctl start "$svc"   && ok "已启动：$svc" ;;
      stop)    systemctl stop "$svc"    && ok "已停止：$svc" ;;
      restart) systemctl restart "$svc" && ok "已重启：$svc" ;;
    esac
  done <<< "$names"
}

cmd_remove() {
  local target="${INSTANCE_NAME:-}"
  local names
  if [ -n "$target" ]; then names="$target"
  else names="$(pick_instance "选择要删除的实例")" || return; fi
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    local svc="${SERVICE_PREFIX}@${name}.service"
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
    rm -f "${INSTANCE_DIR}/${name}.toml"
    rm -f "${LOG_DIR}/${name}.log"
    ok "已删除实例：$name"
  done <<< "$names"
  systemctl daemon-reload
}

# =============================================================================
# cmd_uninstall
# =============================================================================
cmd_uninstall() {
  warn "即将卸载 rust-light-proxy 及全部实例 / 配置 / 日志"
  read -rp "确认卸载？输入 yes 继续：" sure
  [ "$sure" != "yes" ] && { msg "已取消"; return; }

  if [ -d "$INSTANCE_DIR" ]; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      systemctl disable --now "${SERVICE_PREFIX}@${name}.service" >/dev/null 2>&1 || true
    done < <(list_instances)
  fi
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload

  rm -rf "$CONFIG_DIR" "$LOG_DIR" "$INSTALL_DIR"
  rm -f "$LOGROTATE_FILE" "$LOG_CRON_FILE" "$BIN_PATH"
  ok "已卸载并清理完毕"
}

# =============================================================================
# 主菜单
# =============================================================================
menu() {
  while true; do
    banner
    if [ -x "$BIN_PATH" ]; then
      local ver; ver="$($BIN_PATH --version 2>/dev/null | head -n1)"
      msg "  ${C_DIM}已安装：${ver:-未知版本}${C_RESET}"
    else
      msg "  ${C_DIM}未安装：${BIN_PATH}${C_RESET}"
    fi
    msg "  ${C_DIM}架构：$(detect_arch)   实例：${INSTANCE_DIR}${C_RESET}"
    msg "  ${C_DIM}日志：${LOG_DIR}/<name>.log   下载源：${GITHUB_REPO}${C_RESET}"
    hr
    msg "  ${C_CYAN}1)${C_RESET} 添加实例"
    msg "  ${C_CYAN}2)${C_RESET} 查看实例列表"
    msg "  ${C_CYAN}3)${C_RESET} 查看连接信息（客户端 URI）"
    msg "  ${C_CYAN}4)${C_RESET} 启动实例"
    msg "  ${C_CYAN}5)${C_RESET} 停止实例"
    msg "  ${C_CYAN}6)${C_RESET} 重启实例"
    msg "  ${C_CYAN}7)${C_RESET} 查看流量"
    msg "  ${C_CYAN}8)${C_RESET} 删除实例"
    msg "  ${C_CYAN}9)${C_RESET} 设置日志大小上限 ${C_DIM}(当前: $(get_log_limit_mb) MB)${C_RESET}"
    msg "  ${C_CYAN}10)${C_RESET} 更新二进制（从 GitHub Releases）"
    msg "  ${C_CYAN}11)${C_RESET} 卸载并清理全部"
    msg "  ${C_CYAN}0)${C_RESET} 退出"
    hr
    read -rp "请选择操作: " choice
    case "$choice" in
      1)  cmd_add ;;
      2)  cmd_list ;;
      3)  cmd_show ;;
      4)  cmd_action start ;;
      5)  cmd_action stop ;;
      6)  cmd_action restart ;;
      7)  cmd_traffic ;;
      8)  cmd_remove ;;
      9)  cmd_log_limit ;;
      10) cmd_update ;;
      11) cmd_uninstall ;;
      0)  msg "再见"; exit 0 ;;
      *)  warn "无效输入" ;;
    esac
    msg ""; read -rp "按回车返回菜单..." _
  done
}

# =============================================================================
# 用法
# =============================================================================
usage() {
  cat <<EOF
${C_BOLD}用法${C_RESET}
  sudo bash $(basename "$0") [ACTION]

${C_BOLD}交互模式${C_RESET}
  sudo bash $(basename "$0")

${C_BOLD}非交互式环境变量${C_RESET}
  ACTION=menu | add | list | show | traffic | start | stop | restart | remove | log | update | uninstall
  PROXY_TYPE       socks5 | socks5h | http | mixed
  INSTANCE_NAME    实例名称，例如 socks5-1
  LISTEN_ADDR      监听地址，默认 0.0.0.0
  LISTEN_PORT      监听端口
  PROXY_USER       账号
  PROXY_PASS       密码（默认随机）
  MAX_CONNECTIONS  最大并发，0 = 默认 512
  OUTBOUND_PROFILE default | ipv4 | ipv6 | warp
  OUTBOUND_BIND    出口绑定：网口名（eth0）或源 IP；空 = 默认路由 (仅 default profile)
  LOG_LIMIT_MB     日志大小上限（MB），默认 ${DEFAULT_LOG_LIMIT_MB}
  BIN_PATH         二进制路径，默认 ${BIN_PATH}
  CONFIG_DIR       配置目录，默认 ${CONFIG_DIR}
  LOG_DIR          日志目录，默认 ${LOG_DIR}
  GITHUB_REPO      下载源，默认 ${GITHUB_REPO}
  RELEASE_TAG      Release tag，默认 latest

${C_BOLD}WireGuard / Cloudflare WARP 环境变量 (OUTBOUND_PROFILE=warp)${C_RESET}
  WG_PRIVATE_KEY        本机 WireGuard private key       (必填)
  WG_PEER_PUBLIC_KEY    Cloudflare WARP peer public key  (必填)
  WG_ADDR4              本机 IPv4 地址，默认 172.16.0.2/32
  WG_ADDR6              本机 IPv6 地址（可留空）
  WG_ENDPOINT           对端端点，默认 engage.cloudflareclient.com:2408
  WG_ALLOWED_IPS        允许 IP，默认 "0.0.0.0/0, ::/0"
  WG_INTERFACE          内核接口名，默认 warp0
  WG_MARK / WG_TABLE / WG_PRIORITY  SO_MARK / 路由表 / 优先级，默认 1001 / 1001 / 11001
  WG_MTU                MTU，默认 1280
  WG_KEEPALIVE          persistent_keepalive_secs，默认 25

${C_BOLD}示例${C_RESET}
  # 一键远程安装（无需提前下载二进制）
  bash <(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh)

  # 添加 SOCKS5H 实例（推荐 · 域名由代理解析）
  sudo ACTION=add PROXY_TYPE=socks5h INSTANCE_NAME=s5h-1 \\
       LISTEN_PORT=1080 PROXY_USER=u PROXY_PASS=p bash install.sh

  # 添加 mixed 实例并绑定 eth1 出网
  sudo ACTION=add PROXY_TYPE=mixed INSTANCE_NAME=mix-1 \\
       LISTEN_PORT=20950 PROXY_USER=u PROXY_PASS=p OUTBOUND_BIND=eth1 bash install.sh

  # 添加只走 IPv6 出口的 socks5h
  sudo ACTION=add PROXY_TYPE=socks5h INSTANCE_NAME=v6-1 \\
       LISTEN_PORT=2086 PROXY_USER=u PROXY_PASS=p OUTBOUND_PROFILE=ipv6 bash install.sh

  # 添加 Cloudflare WARP 出口（需要 root + CAP_NET_ADMIN）
  sudo ACTION=add PROXY_TYPE=socks5h INSTANCE_NAME=warp-1 \\
       LISTEN_PORT=1089 PROXY_USER=u PROXY_PASS=p OUTBOUND_PROFILE=warp \\
       WG_PRIVATE_KEY=xxxxx WG_PEER_PUBLIC_KEY=yyyyy bash install.sh

  # 查看流量
  sudo ACTION=traffic bash install.sh

  # 设置日志大小上限 200MB
  sudo ACTION=log LOG_LIMIT_MB=200 bash install.sh

  # 在线更新
  sudo ACTION=update bash install.sh

  # 卸载
  sudo ACTION=uninstall bash install.sh
EOF
}

# =============================================================================
# 入口
# =============================================================================
main() {
  require_root
  require_systemd
  install_packages_if_needed

  local action="${ACTION:-${1:-menu}}"
  case "$action" in
    menu)        menu ;;
    add)         banner; cmd_add ;;
    list|ls)     banner; cmd_list ;;
    show|info)   banner; cmd_show ;;
    traffic)     banner; cmd_traffic ;;
    start)       cmd_action start ;;
    stop)        cmd_action stop ;;
    restart)     cmd_action restart ;;
    remove|del)  cmd_remove ;;
    log|loglimit|log-limit)
                 if [ -n "${LOG_LIMIT_MB:-}" ]; then
                   if ! [[ "$LOG_LIMIT_MB" =~ ^[0-9]+$ ]]; then err "LOG_LIMIT_MB 非法：$LOG_LIMIT_MB"; exit 1; fi
                   set_log_limit_mb "$LOG_LIMIT_MB"; apply_log_limit; enforce_log_now
                   ok "日志大小上限已设置为：${LOG_LIMIT_MB} MB"
                 else banner; cmd_log_limit; fi ;;
    update)      banner; install_binary; cmd_update ;;
    uninstall)   cmd_uninstall ;;
    help|-h|--help) usage ;;
    *) err "未知操作：$action"; usage; exit 1 ;;
  esac
}

main "$@"
