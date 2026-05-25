<h1 align="center">🚀 MicaProxy <sup><sub>v3.0.6</sub></sup></h1>

<p align="center">
  轻量、稳定、低占用的 <b>SOCKS5 / SOCKS5 UDP / HTTP / HTTPS</b> 代理服务<br/>
  <sub>Rust + monoio (epoll / io_uring 双驱动) + mimalloc · 支持 Cloudflare WARP / kernel WireGuard 出站</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/language-Rust-orange?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/runtime-monoio%20%2F%20epoll%20%2F%20io__uring-blue" alt="monoio">
  <img src="https://img.shields.io/badge/allocator-mimalloc-purple" alt="mimalloc">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7-success" alt="Arch">
  <img src="https://img.shields.io/badge/glibc-%E2%89%A5%202.28-lightgrey" alt="glibc">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <a href="#-一键安装推荐">一键安装</a> ·
  <a href="#-文件清单">文件清单</a> ·
  <a href="#-systemd-部署">systemd</a> ·
  <a href="#-出站-profile">出站 profile</a> ·
  <a href="#-常见问题">FAQ</a>
</p>

---

## ✨ 特性（v3.0.6）

- 🪶 **轻量** — Release 二进制 ~3.5 MB（已 strip），空闲内存 < 20 MB
- ⚡ **monoio 双驱动** — 默认 `epoll`（避免某些 Linux 6.1 内核把 io_uring 空闲显示成高 `wa`）；可切换 `io_uring`
- 🚀 **mimalloc 分配器** — 高并发短连接场景显著降低分配开销
- 📦 **SOCKS5 完整套件** — TCP CONNECT + **UDP ASSOCIATE**（QUIC / HTTP3 / DNS over UDP 全透传）
- 🌐 **HTTP / HTTPS** — HTTP CONNECT 隧道 + 普通 HTTP `GET http://...` 转发；自动剥离 `Proxy-Authorization` / `Proxy-Connection`
- 🛰️ **命名出站 profile**
  - `default` — 系统默认路由
  - `ipv4` — 只解析 / 连接 IPv4
  - `ipv6` — 只解析 / 连接 IPv6
  - `wireguard_kernel` — 内核 WireGuard 接口（**Cloudflare WARP**），SO_MARK + policy routing，不接管默认路由
- 🔐 **完整认证** — 每 listener 独立 `username` / `password`，**常量时间**对比（`subtle`），抗时序侧信道
- 🧠 **DNS 智能** — 内置 LRU 缓存 + 负向缓存 + 飞行去重；prefer_ipv4 可控
- 🌍 **Happy Eyeballs (RFC 8305)** — IPv4 / IPv6 双栈并发竞速
- 🛡️ **安全卫士** — 每 IP 速率限制、认证失败封禁、慢速握手防护（slowloris）
- 🧵 **多实例** — systemd 模板服务，一台机器跑 N 个独立账号/端口
- 📊 **结构化日志** — 含 `uploaded` / `downloaded` / `duration_ms` 字段
- 🪵 **日志大小硬限制** — 默认 500 MB 上限，可菜单自定义，超过自动清空
- 🔒 **systemd 加固** — `MemoryDenyWriteExecute` + `ProtectSystem=strict` + 受限 CAP（保留 `CAP_NET_ADMIN` 供 WARP/WireGuard）

---

## 📦 一键安装（推荐）

直接在 VPS 上运行，脚本会自动识别架构并从 GitHub Releases 下载二进制：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

> 也可以用 wget：
> ```bash
> wget -qO- https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh | sudo bash
> ```

进入彩色交互菜单后即可完成全部操作：

| # | 功能 | 说明 |
|:-:|---|---|
| 1 | 添加实例 | 协议（**socks5 / http**）、出站 profile（**default / ipv4 / ipv6 / warp**）、端口、账号密码 |
| 2 | 查看实例列表 | 表格显示协议、监听、状态、出站 profile |
| 3 | 查看连接信息 | 打印每个实例的 `socks5h://` / `http://` 客户端 URL |
| 4-6 | 启动 / 停止 / 重启 | 单个或全部 |
| 7 | 查看流量 | 累计 `uploaded` / `downloaded`，含日志当前大小 |
| 8 | 删除实例 | 同时清理 systemd 服务和配置 |
| 9 | 设置日志大小上限 | 默认 **500 MB**，可自定义；超过自动清空 |
| 10 | 更新二进制 | 从 GitHub Releases 拉取最新版并重启实例 |
| 11 | 卸载全部 | 服务、配置、日志、二进制一键清理 |

非交互式快速添加一个 SOCKS5 实例：

```bash
sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=s5-1 \
     LISTEN_PORT=1080 PROXY_USER=myuser PROXY_PASS=mypass \
     bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

---

## 📁 文件清单

| 文件 | 架构 | 适用平台 |
|---|---|---|
| 🛠 `install.sh` | 通用 | 一键安装管理脚本（菜单 + 多实例 + 流量统计） |
| 💻 `micaproxy-linux-amd64` | `x86_64` | 常见 VPS / Intel / AMD 服务器 / 桌面 Linux |
| 📱 `micaproxy-linux-arm64` | `aarch64` | ARM64 服务器、树莓派 4/5、Oracle Ampere、AWS Graviton |
| 🤖 `micaproxy-linux-armv7` | `armv7hf` | 树莓派 2/3、32 位 ARM 路由器/盒子 |

### 🔍 选错了？一行命令搞定

```bash
uname -m
```

| `uname -m` 输出 | 选择文件 |
|---|---|
| `x86_64` | `micaproxy-linux-amd64` |
| `aarch64` / `arm64` | `micaproxy-linux-arm64` |
| `armv7l` / `armv7hl` | `micaproxy-linux-armv7` |

---

## 🔧 构建信息

<table>
<tr><td><b>语言</b></td><td>Rust（stable, 1.94+）</td></tr>
<tr><td><b>异步运行时</b></td><td>monoio（Linux，<b>epoll 默认</b> / 可切 io_uring）+ Tokio</td></tr>
<tr><td><b>内存分配器</b></td><td>mimalloc</td></tr>
<tr><td><b>交叉编译</b></td><td>Rust + zig cc (zig 0.13)</td></tr>
<tr><td><b>glibc 基线</b></td><td><b>2.28</b>（Debian 10 / Ubuntu 18.04 / CentOS 8 / RHEL 8+ 全部兼容）</td></tr>
<tr><td><b>链接方式</b></td><td>动态链接 glibc（仅依赖系统 libc / pthread / dl）</td></tr>
<tr><td><b>优化选项</b></td><td><code>opt-level = 3</code> · <code>lto = thin</code> · <code>panic = abort</code> · <code>strip = true</code></td></tr>
</table>

> ⚠️ 最低 glibc 提升到 **2.28**（因引入 `statx`）。

---

## ⚡ 快速运行（不用脚本）

v3.0.6 起 **必须** 通过配置文件启动（不再支持命令行 listen/mode 参数）：

```bash
# 1. 下载并赋权
mkdir -p /opt/MicaProxy
install -m 0755 micaproxy-linux-amd64 /opt/MicaProxy/MicaProxy

# 2. 写最小配置
cat > /opt/MicaProxy/config.toml <<'EOF'
[[outbounds]]
name = "default"
type = "default"

[[listeners]]
name = "s5-1"
listen = "0.0.0.0:1080"
protocol = "socks5"
outbound = "default"
username = "myuser"
password = "mypassword"

[socks5]
enabled = true
udp_enabled = true
udp_idle_timeout_secs = 120
udp_buffer_bytes = 8192

[runtime]
driver = "epoll"
EOF

# 3. 启动
/opt/MicaProxy/MicaProxy -c /opt/MicaProxy/config.toml
```

客户端就可以用：

```text
socks5h://myuser:mypassword@<server_ip>:1080
```

---

## 🎛 命令行参数

v3.0.6 起 CLI 只剩一个开关：

| 参数 | 说明 |
|---|---|
| `-c, --config <FILE>` | TOML 配置文件路径（**必填**） |
| `-h, --help`          | 帮助 |
| `-V, --version`       | 版本 |

所有 listener / outbound / 认证都在配置文件中声明。

---

## 🧰 systemd 部署

模板服务（`install.sh` 自动生成）：

```ini
[Unit]
Description=MicaProxy instance %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/MicaProxy/MicaProxy -c /etc/MicaProxy/instances/%i.toml
Restart=on-failure
RestartSec=2s
LimitNOFILE=65535

NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=no
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
ReadWritePaths=/opt/MicaProxy/log
ReadOnlyPaths=/opt/MicaProxy/MicaProxy /etc/MicaProxy/instances/%i.toml
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
```

启动 / 停止任意实例：

```bash
sudo systemctl enable --now MicaProxy@s5-1.service
sudo systemctl status      MicaProxy@s5-1.service
sudo systemctl stop        MicaProxy@s5-1.service
```

> ⚠️ `ProtectKernelTunables=no`——v3.0.6 修复 WARP 时引入：MicaProxy 启动 WireGuard 出站时需要写 `net.ipv4.conf.*.{src_valid_mark,rp_filter}` 等 sysctl。普通 SOCKS5/HTTP 不写任何 sysctl。

---

## 🧪 测试

```bash
# SOCKS5H（远程 DNS）
curl -x socks5h://myuser:mypassword@<server_ip>:1080 https://example.com

# HTTP CONNECT
curl -x http://myuser:mypassword@<server_ip>:8080 https://example.com

# 普通 HTTP 转发
curl -x http://myuser:mypassword@<server_ip>:8080 http://example.com

# SOCKS5 UDP（QUIC over HTTP/3 站点）
curl --http3 -x socks5h://myuser:mypassword@<server_ip>:1080 https://cloudflare-quic.com
```

服务端日志应输出类似：

```text
proto=socks5 target=example.com:443 uploaded=12345 downloaded=67890 duration_ms=1023 status=ok
```

---

## 🛰️ 出站 profile

v3 起支持**命名出站 profile**，让不同的 listener 走完全不同的出口路径，无需多个进程：

| profile | 类型 | 说明 |
|---|---|---|
| `default` | 系统默认路由 | 普通使用 |
| `ipv4` | IPv4-only | DNS 仅解析 A 记录，连接仅走 IPv4 |
| `ipv6` | IPv6-only | DNS 仅解析 AAAA 记录，连接仅走 IPv6 |
| `wireguard_kernel` | Linux kernel WireGuard | Cloudflare WARP / 自建 WG，**SO_MARK + policy routing**，不接管默认路由 |

### 协议语义说明（v3.0.2 后简化）

| 协议 | 客户端目标 | 谁解析 DNS |
|---|---|---|
| `socks5` | IP **或** 域名（自动识别 ATYP） | ATYP=DOMAIN 时由**代理端**解析（受 profile 控制） |
| `http`   | HTTP CONNECT 或普通 HTTP        | **代理端** |

> ✨ v3.0.2 起 `socks5h` 已和 `socks5` 合并 —— 客户端无论传 IP 还是域名都正常工作；想让代理解析 DNS（推荐），客户端写 `socks5h://...` 即可。

### Cloudflare WARP 一键配置

```bash
# 交互菜单：添加实例 → 协议选 1 (SOCKS5) → 出站 profile 选 4 (warp)
sudo bash install.sh

# 非交互（提前注册好 WARP，拿到 private/peer pubkey）：
sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=warp-1 \
     LISTEN_PORT=1089 PROXY_USER=u PROXY_PASS=p \
     OUTBOUND_PROFILE=warp \
     WG_PRIVATE_KEY='你的WG私钥' \
     WG_PEER_PUBLIC_KEY='WARP对端公钥' \
     bash install.sh
```

WARP profile 通过 **SO_MARK + 策略路由表** 选择出口，避免改动主默认路由——其他实例完全不受影响。

WARP UDP 默认偏好 IPv6（`udp_prefer_ipv6 = true`）以避免某些 WARP endpoint 的 UDP IPv4 死路径。

---

## 🪵 日志大小限制

- **默认上限：500 MB**（强制生效，无需配置）
- 日志路径：`/opt/MicaProxy/log/<instance>.log`
- 实现机制（双重保险）：
  1. 写入 `logrotate` 配置 `size <N>M` + `copytruncate`（系统有 `logrotate` 时启用）
  2. 写入 `/etc/cron.d/MicaProxy-logrotate`，**每分钟**检查一次，超过阈值即 `truncate` 清空
- 超过上限时直接 **清空文件重新写入**（流量统计同时归零）

修改上限（菜单第 9 项）：

```bash
# 交互菜单
sudo bash install.sh    # 选 9

# 非交互一行命令
sudo ACTION=log LOG_LIMIT_MB=200 bash install.sh
```

---

## ✅ 已实现 / ❌ 暂未实现

<table>
<tr>
<th>✅ v3.0.6 已实现</th>
<th>🛣 后续路线</th>
</tr>
<tr>
<td valign="top">

- SOCKS5 TCP CONNECT（自动识别 IP / 域名）
- **SOCKS5 UDP ASSOCIATE**（QUIC / HTTP3 / DNS）
- SOCKS5 用户名/密码认证（RFC 1929）
- HTTP CONNECT + 普通 HTTP 转发（Basic 认证）
- 多 listener 独立账号 / 协议 / 出站
- 命名出站 profile：default / ipv4 / ipv6 / wireguard_kernel
- **Cloudflare WARP 出口**（TCP + UDP，SO_MARK + policy routing）
- monoio 双驱动（epoll 默认 / io_uring 可选）
- mimalloc 分配器
- DNS LRU + 负向缓存 + 飞行去重
- Happy Eyeballs IPv4/IPv6 双栈竞速
- 握手 / 连接 / 空闲三段超时
- 最大并发限制 + 每 IP 速率限制
- 认证失败封禁 / slowloris 防护
- 常量时间认证对比（抗时序）
- 结构化访问日志 + UDP metrics

</td>
<td valign="top">

- HTTP/3 MASQUE / CONNECT-UDP
- Prometheus metrics（部分已就绪）
- ACL / 端口黑名单
- 配置热重载
- Web 管理界面
- musl 静态构建版本

</td>
</tr>
</table>

---

## ❓ 常见问题

<details>
<summary><b>启动报 <code>GLIBC_2.28 not found</code></b></summary>
<br/>
本地 glibc 低于 2.28（CentOS 7 / Ubuntu 16.04 等）。请升级到 Debian 10 / Ubuntu 18.04 / CentOS 8 及以上。
</details>

<details>
<summary><b><code>top</code> / <code>vmstat</code> 显示 <code>wa</code> 高达 90%+</b></summary>
<br/>

某些 Linux 6.1 内核会把 io_uring 的空闲等待计入 iowait。v3.0.3 已将默认驱动切到 <code>epoll</code>，应该看不到这个现象。如果你显式切到 io_uring 又遇到此问题，可以改回：

```toml
[runtime]
driver = "epoll"
```

</details>

<details>
<summary><b>WARP 配置后 normal listener 卡住</b></summary>
<br/>
v3.0.6 修复了此问题：WARP 出站的 TCP fd 现在统一加 <code>O_NONBLOCK</code>，不会再阻塞同一 monoio 线程上的其他 listener。请确认你用的是 v3.0.6+。
</details>

<details>
<summary><b>提示 <code>address already in use</code></b></summary>
<br/>

换个端口，或排查占用：

```bash
ss -lntp | grep 1080
```

</details>

<details>
<summary><b>客户端连不上</b></summary>
<br/>
检查防火墙（<code>ufw</code> / <code>firewalld</code> / 云厂商安全组）是否放行了监听端口。SOCKS5 UDP 还要放行同端口 UDP。
</details>

<details>
<summary><b>认证失败</b></summary>
<br/>
v3.0.2 起认证字段在 <b>每个 listener 内部</b>（不再有全局 <code>[auth]</code>）：
<pre><code>[[listeners]]
name = "s5-1"
listen = "0.0.0.0:1080"
protocol = "socks5"
outbound = "default"
username = "myuser"
password = "mypassword"
</code></pre>
</details>

<details>
<summary><b>如何校验文件完整性</b></summary>
<br/>

```bash
sha256sum micaproxy-linux-*
```

</details>

---

## 📜 协议

[MIT](LICENSE) © judy-gotv

<p align="center">
  <sub>用 ❤️ 与 🦀 打造</sub>
</p>
