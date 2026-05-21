#!/usr/bin/env bash
# =============================================================================
#  Rust Light Proxy - 一键安装管理脚本
#  适用：Debian / Ubuntu / CentOS / RHEL / Fedora / Alpine / Arch
#  架构：amd64 / arm64 / armv7
# =============================================================================

set -o pipefail

# ----- 颜色 ------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RESET="$(tput sgr0)"
  C_BOLD="$(tput bold)"
  C_DIM="$(tput dim)"
  C_RED="$(tput setaf 1)"
  C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)"
  C_MAGENTA="$(tput setaf 5)"
  C_CYAN="$(tput setaf 6)"
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""
fi

msg()  { printf '%s\n' "$*"; }
info() { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
hint() { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_RESET"; }

hr() {
  printf '%s' "$C_DIM"
  printf '%.0s─' $(seq 1 60)
  printf '%s\n' "$C_RESET"
}

banner() {
  clear 2>/dev/null || true
  cat <<EOF
${C_CYAN}${C_BOLD}
╔════════════════════════════════════════════════════════════╗
║          Rust Light Proxy  ·  一键安装管理脚本              ║
║          SOCKS5 / SOCKS5H / HTTP CONNECT                   ║
╚════════════════════════════════════════════════════════════╝${C_RESET}
EOF
}

# ----- 全局变量（可被环境变量覆盖） -------------------------------------------
BIN_PATH="${BIN_PATH:-/usr/local/bin/rust-light-proxy}"
CONFIG_DIR="${CONFIG_DIR:-/etc/rust-light-proxy}"
INSTANCE_DIR="${CONFIG_DIR}/instances"
SERVICE_PREFIX="${SERVICE_PREFIX:-rust-light-proxy}"   # rust-light-proxy@<name>.service
SERVICE_FILE="/etc/systemd/system/${SERVICE_PREFIX}@.service"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub Releases 下载源
GITHUB_REPO="${GITHUB_REPO:-judy-gotv/Rust-SOCKS5-HTTP}"
RELEASE_TAG="${RELEASE_TAG:-latest}"     # latest 或具体 tag，例如 v0.1.0

# ----- 工具函数 ---------------------------------------------------------------
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
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64)            echo "amd64" ;;
    aarch64|arm64)           echo "arm64" ;;
    armv7l|armv7|armhf)      echo "armv7" ;;
    armv6l)                  echo "armv7" ;;   # 退化兼容
    *)
      err "不支持的架构：$m"
      exit 1
      ;;
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
  # 10000-60000 之间随机
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

install_packages_if_needed() {
  if command_exists curl && command_exists ss; then return; fi
  if command_exists apt-get; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends ca-certificates curl iproute2 >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf install -y ca-certificates curl iproute >/dev/null 2>&1 || true
  elif command_exists yum; then
    yum install -y ca-certificates curl iproute >/dev/null 2>&1 || true
  elif command_exists apk; then
    apk add --no-cache ca-certificates curl iproute2 >/dev/null 2>&1 || true
  elif command_exists pacman; then
    pacman -Sy --noconfirm ca-certificates curl iproute2 >/dev/null 2>&1 || true
  fi
}

# ----- 二进制安装 -------------------------------------------------------------
download_file() {
  local url="$1" dst="$2"
  if command_exists curl; then
    curl -fSL --retry 3 --connect-timeout 10 -o "$dst" "$url"
  elif command_exists wget; then
    wget -O "$dst" "$url"
  else
    err "需要 curl 或 wget 才能下载文件。"
    return 1
  fi
}

resolve_release_url() {
  # 解析 GitHub Releases 下载 URL
  local arch="$1" tag="$2"
  local asset="rust-light-proxy-linux-${arch}"
  if [ "$tag" = "latest" ]; then
    echo "https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
  else
    echo "https://github.com/${GITHUB_REPO}/releases/download/${tag}/${asset}"
  fi
}

install_binary() {
  if [ -x "$BIN_PATH" ]; then
    return 0
  fi

  local arch
  arch="$(detect_arch)"
  info "本机架构：${arch}"

  # 1. 先尝试脚本同目录的二进制（离线场景）
  local local_candidates=(
    "${SCRIPT_DIR}/rust-light-proxy-linux-${arch}"
    "${SCRIPT_DIR}/rust-light-proxy"
    "./rust-light-proxy-linux-${arch}"
    "./rust-light-proxy"
  )
  for c in "${local_candidates[@]}"; do
    if [ -f "$c" ]; then
      info "使用本地二进制：$c"
      install -m 0755 "$c" "$BIN_PATH"
      info "二进制已安装到：${BIN_PATH}"
      return 0
    fi
  done

  # 2. 从 GitHub Releases 下载
  local url tmp
  url="$(resolve_release_url "$arch" "$RELEASE_TAG")"
  tmp="$(mktemp)"
  info "正在从 GitHub Releases 下载：${url}"
  if ! download_file "$url" "$tmp"; then
    err "下载失败。请检查网络或手动下载到脚本同目录："
    hint "$url"
    rm -f "$tmp"
    exit 1
  fi

  if [ ! -s "$tmp" ]; then
    err "下载文件为空。"
    rm -f "$tmp"
    exit 1
  fi

  # 简单校验：是 ELF 文件
  if ! head -c 4 "$tmp" | grep -q $'\x7fELF'; then
    err "下载的文件不是有效的 ELF 二进制，可能是 404 HTML 页面。"
    hint "URL: $url"
    rm -f "$tmp"
    exit 1
  fi

  install -m 0755 "$tmp" "$BIN_PATH"
  rm -f "$tmp"
  info "二进制已安装到：${BIN_PATH}"
}

# ----- 更新二进制 -------------------------------------------------------------
cmd_update() {
  local arch
  arch="$(detect_arch)"
  local url tmp
  url="$(resolve_release_url "$arch" "$RELEASE_TAG")"
  tmp="$(mktemp)"

  info "正在下载最新版本：${url}"
  if ! download_file "$url" "$tmp"; then
    err "下载失败。"
    rm -f "$tmp"
    return 1
  fi
  if ! head -c 4 "$tmp" | grep -q $'\x7fELF'; then
    err "下载的文件不是有效的 ELF 二进制。"
    rm -f "$tmp"
    return 1
  fi

  install -m 0755 "$tmp" "$BIN_PATH"
  rm -f "$tmp"
  info "二进制已更新：$($BIN_PATH --version 2>/dev/null | head -n1)"

  # 重启所有实例
  local names
  names="$(list_instances)"
  if [ -n "$names" ]; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      systemctl restart "${SERVICE_PREFIX}@${name}.service" >/dev/null 2>&1 || true
      info "已重启实例：$name"
    done <<< "$names"
  fi
}

# ----- systemd 模板 -----------------------------------------------------------
write_template_service() {
  if [ -f "$SERVICE_FILE" ]; then
    return
  fi
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Rust Light Proxy (%i)
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} -c ${INSTANCE_DIR}/%i.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

# ----- 实例配置 ---------------------------------------------------------------
list_instances() {
  if [ ! -d "$INSTANCE_DIR" ]; then return; fi
  find "$INSTANCE_DIR" -maxdepth 1 -type f -name '*.toml' -printf '%f\n' 2>/dev/null \
    | sed 's/\.toml$//' | sort
}

write_instance_config() {
  local name="$1" mode="$2" listen_addr="$3" port="$4"
  local user="$5" pass="$6" max_conn="$7"

  mkdir -p "$INSTANCE_DIR"
  chmod 0755 "$CONFIG_DIR" "$INSTANCE_DIR"

  local http_enabled="false"
  if [ "$mode" = "http" ]; then http_enabled="true"; fi

  local auth_enabled="true"
  if [ -z "$user" ] || [ -z "$pass" ]; then auth_enabled="false"; fi

  cat > "${INSTANCE_DIR}/${name}.toml" <<EOF
# rust-light-proxy 实例：${name}
[server]
listen = "${listen_addr}:${port}"
mode = "${mode}"

# 最大并发连接数，0 表示不限制
max_connections = ${max_conn}

connect_timeout_secs = 10
idle_timeout_secs = 300
handshake_timeout_secs = 10

[auth]
enabled = ${auth_enabled}
username = "${user}"
password = "${pass}"

[socks5]
enabled = true
udp_enabled = false
remote_dns = true

[http]
enabled = ${http_enabled}
connect_only = true
max_header_bytes = 8192

[dns]
prefer_ipv4 = true
cache_enabled = false
cache_ttl_secs = 300

[logging]
level = "info"
access_log = true

[runtime]
worker_threads = 2
max_blocking_threads = 8
EOF
  chmod 0600 "${INSTANCE_DIR}/${name}.toml"
}

instance_exists() {
  [ -f "${INSTANCE_DIR}/$1.toml" ]
}

# ----- 子命令：添加实例 -------------------------------------------------------
cmd_add() {
  local proxy_type="${PROXY_TYPE:-}"
  local name="${INSTANCE_NAME:-}"
  local listen_addr="${LISTEN_ADDR:-0.0.0.0}"
  local port="${LISTEN_PORT:-}"
  local user="${PROXY_USER:-}"
  local pass="${PROXY_PASS:-}"
  local max_conn="${MAX_CONNECTIONS:-0}"

  if [ -z "$proxy_type" ]; then
    msg ""
    msg "${C_BOLD}选择代理协议${C_RESET}"
    msg "  ${C_CYAN}1)${C_RESET} SOCKS5 ${C_DIM}(支持 socks5h 远程 DNS)${C_RESET}"
    msg "  ${C_CYAN}2)${C_RESET} HTTP CONNECT"
    read -rp "请选择 [1-2，默认 1]: " sel
    case "${sel:-1}" in
      1) proxy_type="socks5" ;;
      2) proxy_type="http" ;;
      *) proxy_type="socks5" ;;
    esac
  fi

  if [ "$proxy_type" != "socks5" ] && [ "$proxy_type" != "http" ]; then
    err "未知的 PROXY_TYPE：$proxy_type（应为 socks5 / http）"
    exit 1
  fi

  if [ -z "$name" ]; then
    local default_name
    local idx=1
    while :; do
      default_name="${proxy_type}-${idx}"
      instance_exists "$default_name" || break
      idx=$((idx + 1))
    done
    read -rp "实例名称 [${default_name}]: " name
    name="${name:-$default_name}"
  fi

  if [[ ! "$name" =~ ^[A-Za-z0-9_.\-]+$ ]]; then
    err "实例名称只能包含字母数字、下划线、点、短横线：$name"
    exit 1
  fi

  if instance_exists "$name"; then
    err "实例已存在：$name"
    exit 1
  fi

  if [ -z "$port" ]; then
    local default_port
    default_port="$(random_port)"
    read -rp "监听端口 [${default_port}]: " port
    port="${port:-$default_port}"
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    err "端口非法：$port"
    exit 1
  fi

  if [ -z "$user" ]; then
    read -rp "代理账号 [user]: " user
    user="${user:-user}"
  fi

  if [ -z "$pass" ]; then
    local default_pass
    default_pass="$(random_password)"
    read -rp "代理密码 [回车使用随机: ${default_pass}]: " pass
    pass="${pass:-$default_pass}"
  fi

  if [ -z "$max_conn" ]; then max_conn=0; fi
  if ! [[ "$max_conn" =~ ^[0-9]+$ ]]; then
    err "最大并发连接数非法：$max_conn"
    exit 1
  fi

  install_binary
  write_template_service
  write_instance_config "$name" "$proxy_type" "$listen_addr" "$port" "$user" "$pass" "$max_conn"

  local svc="${SERVICE_PREFIX}@${name}.service"
  systemctl daemon-reload
  systemctl enable --now "$svc" >/dev/null 2>&1 || systemctl restart "$svc"

  sleep 1
  if systemctl is-active --quiet "$svc"; then
    info "实例已启动：$svc"
  else
    warn "实例启动失败，请查看：journalctl -u $svc -n 50"
  fi

  local ip
  ip="$(detect_public_ip)"
  local scheme="socks5h"
  [ "$proxy_type" = "http" ] && scheme="http"

  hr
  msg "${C_BOLD}${C_GREEN}实例信息${C_RESET}"
  printf "  %-14s %s\n" "名称"     "$name"
  printf "  %-14s %s\n" "协议"     "$proxy_type"
  printf "  %-14s %s\n" "监听"     "${listen_addr}:${port}"
  printf "  %-14s %s\n" "账号"     "$user"
  printf "  %-14s %s\n" "密码"     "$pass"
  printf "  %-14s %s\n" "最大并发" "$( [ "$max_conn" = "0" ] && echo "不限制" || echo "$max_conn" )"
  printf "  %-14s %s\n" "服务"     "$svc"
  hr
  msg "${C_BOLD}客户端 URI${C_RESET}"
  msg "  ${C_CYAN}${scheme}://${user}:${pass}@${ip}:${port}${C_RESET}"
  hr
}

# ----- 子命令：列表 -----------------------------------------------------------
cmd_list() {
  local names
  names="$(list_instances)"
  if [ -z "$names" ]; then
    warn "暂无实例。可使用「添加实例」创建。"
    return
  fi

  hr
  printf "${C_BOLD}%-20s %-8s %-22s %-10s %s${C_RESET}\n" "名称" "协议" "监听" "状态" "服务"
  hr

  while IFS= read -r name; do
    local cfg="${INSTANCE_DIR}/${name}.toml"
    local mode listen status svc color
    mode="$(grep -E '^mode' "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    listen="$(grep -E '^listen' "$cfg" | head -n1 | sed -E 's/.*"(.*)".*/\1/')"
    svc="${SERVICE_PREFIX}@${name}.service"
    if systemctl is-active --quiet "$svc"; then
      status="running"; color="$C_GREEN"
    else
      status="stopped"; color="$C_RED"
    fi
    printf "%-20s %-8s %-22s ${color}%-10s${C_RESET} %s\n" "$name" "$mode" "$listen" "$status" "$svc"
  done <<< "$names"
  hr
}

# ----- 子命令：流量统计 -------------------------------------------------------
cmd_traffic() {
  local names
  names="$(list_instances)"
  if [ -z "$names" ]; then
    warn "暂无实例。"
    return
  fi

  hr
  printf "${C_BOLD}%-20s %-14s %-14s %-10s${C_RESET}\n" "名称" "上传(累计)" "下载(累计)" "连接数"
  hr

  while IFS= read -r name; do
    local svc="${SERVICE_PREFIX}@${name}.service"
    # 累加日志中的 uploaded= / downloaded=
    local stats
    stats="$(journalctl -u "$svc" --no-pager -o cat 2>/dev/null \
      | awk '
        {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^uploaded=/)        { split($i, a, "="); up += a[2] + 0 }
            if ($i ~ /^upload_bytes=/)    { split($i, a, "="); up += a[2] + 0 }
            if ($i ~ /^uploaded_bytes=/)  { split($i, a, "="); up += a[2] + 0 }
            if ($i ~ /^downloaded=/)      { split($i, a, "="); dn += a[2] + 0 }
            if ($i ~ /^download_bytes=/)  { split($i, a, "="); dn += a[2] + 0 }
            if ($i ~ /^downloaded_bytes=/){ split($i, a, "="); dn += a[2] + 0 }
            if ($i ~ /^status=/)          { conn += 1 }
          }
        }
        END { printf "%d %d %d", up + 0, dn + 0, conn + 0 }')"

    local up dn conn
    up="$(echo "$stats"  | awk '{print $1}')"
    dn="$(echo "$stats"  | awk '{print $2}')"
    conn="$(echo "$stats"| awk '{print $3}')"
    printf "%-20s %-14s %-14s %-10s\n" "$name" "$(human_bytes "$up")" "$(human_bytes "$dn")" "$conn"
  done <<< "$names"
  hr
  hint "数据来源：journalctl 中的 access log 累计，重启服务或日志轮转后会重新计数。"
}

human_bytes() {
  local b="${1:-0}"
  if [ "$b" -lt 1024 ]; then
    echo "${b} B"
  elif [ "$b" -lt 1048576 ]; then
    awk -v b="$b" 'BEGIN{printf "%.2f KB", b/1024}'
  elif [ "$b" -lt 1073741824 ]; then
    awk -v b="$b" 'BEGIN{printf "%.2f MB", b/1048576}'
  elif [ "$b" -lt 1099511627776 ]; then
    awk -v b="$b" 'BEGIN{printf "%.2f GB", b/1073741824}'
  else
    awk -v b="$b" 'BEGIN{printf "%.2f TB", b/1099511627776}'
  fi
}

# ----- 子命令：启停 -----------------------------------------------------------
pick_instance() {
  local prompt="${1:-请选择实例}"
  local names
  names="$(list_instances)"
  if [ -z "$names" ]; then
    warn "暂无实例。"
    return 1
  fi
  msg ""
  msg "${C_BOLD}${prompt}${C_RESET}"
  local i=0
  local arr=()
  while IFS= read -r n; do
    i=$((i+1))
    arr+=("$n")
    printf "  ${C_CYAN}%2d)${C_RESET} %s\n" "$i" "$n"
  done <<< "$names"
  printf "  ${C_CYAN}%2d)${C_RESET} 全部\n" "$((i+1))"
  read -rp "请选择 [1-$((i+1))]: " sel
  if [ "$sel" = "$((i+1))" ]; then
    printf '%s\n' "${arr[@]}"
    return 0
  fi
  if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$i" ]; then
    echo "${arr[$((sel-1))]}"
    return 0
  fi
  err "选择无效。"
  return 1
}

cmd_action() {
  local action="$1"
  local target="${INSTANCE_NAME:-}"
  local names

  if [ -n "$target" ]; then
    names="$target"
  else
    names="$(pick_instance "选择要 ${action} 的实例")" || return
  fi

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    local svc="${SERVICE_PREFIX}@${name}.service"
    case "$action" in
      start)   systemctl start "$svc"   && info "已启动：$svc" ;;
      stop)    systemctl stop "$svc"    && info "已停止：$svc" ;;
      restart) systemctl restart "$svc" && info "已重启：$svc" ;;
    esac
  done <<< "$names"
}

# ----- 子命令：删除单实例 -----------------------------------------------------
cmd_remove() {
  local target="${INSTANCE_NAME:-}"
  local names
  if [ -n "$target" ]; then
    names="$target"
  else
    names="$(pick_instance "选择要删除的实例")" || return
  fi

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    local svc="${SERVICE_PREFIX}@${name}.service"
    systemctl disable --now "$svc" >/dev/null 2>&1 || true
    rm -f "${INSTANCE_DIR}/${name}.toml"
    info "已删除实例：$name"
  done <<< "$names"
  systemctl daemon-reload
}

# ----- 子命令：卸载 -----------------------------------------------------------
cmd_uninstall() {
  warn "即将卸载 rust-light-proxy 及其全部实例。"
  read -rp "确认卸载？输入 yes 继续：" sure
  if [ "$sure" != "yes" ]; then
    msg "已取消。"
    return
  fi

  if [ -d "$INSTANCE_DIR" ]; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      systemctl disable --now "${SERVICE_PREFIX}@${name}.service" >/dev/null 2>&1 || true
    done < <(list_instances)
  fi
  systemctl disable --now "${SERVICE_PREFIX}.service" >/dev/null 2>&1 || true

  rm -f "$SERVICE_FILE"
  rm -f "/etc/systemd/system/${SERVICE_PREFIX}.service"
  systemctl daemon-reload

  rm -rf "$CONFIG_DIR"
  rm -f "$BIN_PATH"

  info "已卸载并清理完毕。"
}

# ----- 菜单 -------------------------------------------------------------------
menu() {
  while true; do
    banner
    if [ -x "$BIN_PATH" ]; then
      ver="$($BIN_PATH --version 2>/dev/null | head -n1)"
      msg "  ${C_DIM}已安装：${ver}${C_RESET}"
    else
      msg "  ${C_DIM}未安装：${BIN_PATH}${C_RESET}"
    fi
    msg "  ${C_DIM}架构：$(detect_arch)   实例目录：${INSTANCE_DIR}${C_RESET}"
    hr
    msg "  ${C_CYAN}1)${C_RESET} 添加实例"
    msg "  ${C_CYAN}2)${C_RESET} 查看实例列表"
    msg "  ${C_CYAN}3)${C_RESET} 启动实例"
    msg "  ${C_CYAN}4)${C_RESET} 停止实例"
    msg "  ${C_CYAN}5)${C_RESET} 重启实例"
    msg "  ${C_CYAN}6)${C_RESET} 查看流量"
    msg "  ${C_CYAN}7)${C_RESET} 删除实例"
    msg "  ${C_CYAN}8)${C_RESET} 更新二进制（从 GitHub Releases）"
    msg "  ${C_CYAN}9)${C_RESET} 卸载并清理全部"
    msg "  ${C_CYAN}0)${C_RESET} 退出"
    hr
    read -rp "请选择操作: " choice
    case "$choice" in
      1) cmd_add ;;
      2) cmd_list ;;
      3) cmd_action start ;;
      4) cmd_action stop ;;
      5) cmd_action restart ;;
      6) cmd_traffic ;;
      7) cmd_remove ;;
      8) cmd_update ;;
      9) cmd_uninstall ;;
      0) msg "再见。"; exit 0 ;;
      *) warn "无效输入。" ;;
    esac
    msg ""
    read -rp "按回车返回菜单..." _
  done
}

# ----- 入口 -------------------------------------------------------------------
usage() {
  cat <<EOF
${C_BOLD}用法${C_RESET}
  sudo bash $(basename "$0") [ACTION]

${C_BOLD}交互模式${C_RESET}
  sudo bash $(basename "$0")

${C_BOLD}非交互式环境变量${C_RESET}
  ACTION=menu | add | list | traffic | start | stop | restart | remove | update | uninstall
  PROXY_TYPE       socks5 | http
  INSTANCE_NAME    实例名称，例如 socks5-1
  LISTEN_ADDR      监听地址，默认 0.0.0.0
  LISTEN_PORT      监听端口
  PROXY_USER       账号
  PROXY_PASS       密码（默认随机）
  MAX_CONNECTIONS  最大并发，默认 0 表示不限制
  BIN_PATH         二进制安装路径，默认 /usr/local/bin/rust-light-proxy
  CONFIG_DIR       配置目录，默认 /etc/rust-light-proxy
  SERVICE_PREFIX   systemd 服务前缀，默认 rust-light-proxy
  GITHUB_REPO      下载仓库，默认 ${GITHUB_REPO}
  RELEASE_TAG      Release tag，默认 latest

${C_BOLD}示例${C_RESET}
  # 一键远程安装（无需提前下载二进制）
  bash <(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh)

  # 添加一个 SOCKS5 实例
  sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=socks5-1 \\
       LISTEN_PORT=1080 PROXY_USER=myuser PROXY_PASS=mypass bash $(basename "$0")

  # 添加一个 HTTP CONNECT 实例
  sudo ACTION=add PROXY_TYPE=http   INSTANCE_NAME=http-1 \\
       LISTEN_PORT=8080 PROXY_USER=myuser PROXY_PASS=mypass bash $(basename "$0")

  # 查看流量
  sudo ACTION=traffic bash $(basename "$0")

  # 卸载
  sudo ACTION=uninstall bash $(basename "$0")
EOF
}

main() {
  require_root
  require_systemd
  install_packages_if_needed

  local action="${ACTION:-${1:-menu}}"

  case "$action" in
    menu)        menu ;;
    add)         banner; cmd_add ;;
    list|ls)     banner; cmd_list ;;
    traffic)     banner; cmd_traffic ;;
    start)       cmd_action start ;;
    stop)        cmd_action stop ;;
    restart)     cmd_action restart ;;
    remove|del)  cmd_remove ;;
    update)      banner; install_binary; cmd_update ;;
    uninstall)   cmd_uninstall ;;
    help|-h|--help) usage ;;
    *) err "未知操作：$action"; usage; exit 1 ;;
  esac
}

main "$@"
