<h1 align="center">🚀 Rust Light Proxy <sup><sub>v2</sub></sup></h1>

<p align="center">
  轻量、稳定、低占用的 <b>SOCKS5 / SOCKS5H / HTTP CONNECT</b> 代理服务<br/>
  <sub>Rust + monoio (Linux io_uring) + mimalloc，单二进制，开箱即用</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/language-Rust-orange?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/runtime-monoio%20%2F%20io__uring-blue" alt="monoio">
  <img src="https://img.shields.io/badge/allocator-mimalloc-purple" alt="mimalloc">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7-success" alt="Arch">
  <img src="https://img.shields.io/badge/glibc-%E2%89%A5%202.28-lightgrey" alt="glibc">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <a href="#-一键安装推荐">一键安装</a> ·
  <a href="#-文件清单">文件清单</a> ·
  <a href="#-命令行参数">命令行</a> ·
  <a href="#-systemd-部署">systemd</a> ·
  <a href="#-常见问题">FAQ</a>
</p>

---

## ✨ 特性（v2 全新升级）

- 🪶 **轻量** — Release 二进制 ~2 MB（已 strip），空闲内存 < 20 MB
- ⚡ **极致性能** — Linux 下基于 **monoio + io_uring**，TCP 转发走 **splice() 零拷贝**
- 🚀 **mimalloc 分配器** — 高并发短连接场景显著降低分配开销
- 🔐 **完整认证** — SOCKS5 用户名/密码、HTTP Basic，**常量时间**对比（`subtle`），抗时序侧信道
- 🌐 **SOCKS5H 远程 DNS** — DOMAIN 在服务端解析；内置 LRU 缓存 + 负向缓存 + 飞行去重
- 🌍 **Happy Eyeballs (RFC 8305)** — IPv4 / IPv6 双栈并发竞速，连接更快
- 🧩 **三协议合一** — `socks5` / `http` / `mixed`（单端口自动识别）
- 🛰️ **指定出口网口/IP** — `SO_BINDTODEVICE`，多网卡机器可绑接口出网（自动检测网口）
- 🛡️ **安全卫士** — 每 IP 速率限制、认证失败封禁、慢速握手防护（slowloris）
- 🧵 **多实例** — systemd 模板服务，一台机器跑 N 个独立账号/端口
- 📊 **结构化日志** — 含 `uploaded` / `downloaded` / `duration_ms` 字段
- 🪵 **日志大小硬限制** — 默认 500 MB 上限，可菜单自定义，超过自动清空
- 🔒 **systemd 加固** — `DynamicUser` + `MemoryDenyWriteExecute` + `ProtectSystem=strict`

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
| 1 | 添加实例 | 选择协议（socks5 / http / **mixed**）、端口、账号密码、出口网口 |
| 2 | 查看实例列表 | 表格显示协议、监听、运行状态 |
| 3-5 | 启动 / 停止 / 重启 | 单个或全部 |
| 6 | 查看流量 | 累计 `uploaded` / `downloaded`，含日志当前大小 |
| 7 | 删除实例 | 同时清理 systemd 服务和配置 |
| 8 | 设置日志大小上限 | 默认 **500 MB**，可自定义；超过自动清空 |
| 9 | 更新二进制 | 从 GitHub Releases 拉取最新版并重启实例 |
| 10 | 卸载全部 | 服务、配置、日志、二进制一键清理 |
| 11 | 查看连接信息 | 打印每个实例的 `socks5h://` / `http://` 连接 URL |

非交互式快速添加一个 SOCKS5 实例：

```bash
sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=socks5-1 \
     LISTEN_PORT=1080 PROXY_USER=myuser PROXY_PASS=mypass \
     bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

---

## 📁 文件清单

| 文件 | 架构 | 适用平台 |
|---|---|---|
| 🛠 `install.sh` | 通用 | 一键安装管理脚本（菜单 + 多实例 + 流量统计） |
| 💻 `rust-light-proxy-linux-amd64` | `x86_64` | 常见 VPS / Intel / AMD 服务器 / 桌面 Linux |
| 📱 `rust-light-proxy-linux-arm64` | `aarch64` | ARM64 服务器、树莓派 4/5、Oracle Ampere、AWS Graviton |
| 🤖 `rust-light-proxy-linux-armv7` | `armv7hf` | 树莓派 2/3、32 位 ARM 路由器/盒子 |

### 🔍 选错了？一行命令搞定

```bash
uname -m
```

| `uname -m` 输出 | 选择文件 |
|---|---|
| `x86_64` | `rust-light-proxy-linux-amd64` |
| `aarch64` / `arm64` | `rust-light-proxy-linux-arm64` |
| `armv7l` / `armv7hl` | `rust-light-proxy-linux-armv7` |

---

## 🔧 构建信息

<table>
<tr><td><b>语言</b></td><td>Rust（stable, 1.94+）</td></tr>
<tr><td><b>异步运行时</b></td><td>monoio（Linux io_uring）+ Tokio</td></tr>
<tr><td><b>内存分配器</b></td><td>mimalloc</td></tr>
<tr><td><b>交叉编译</b></td><td>Rust + zig cc (zig 0.13)</td></tr>
<tr><td><b>glibc 基线</b></td><td><b>2.28</b>（Debian 10 / Ubuntu 18.04 / CentOS 8 / RHEL 8+ 全部兼容）</td></tr>
<tr><td><b>链接方式</b></td><td>动态链接 glibc（仅依赖系统 libc / pthread / dl）</td></tr>
<tr><td><b>优化选项</b></td><td><code>opt-level = 3</code> · <code>lto = thin</code> · <code>panic = abort</code> · <code>strip = true</code></td></tr>
</table>

> ⚠️ v2 起最低 glibc 提升到 **2.28**（因引入 `statx`）。如需在更老的系统运行，可自行编译 musl 静态版本。

---

## ⚡ 快速运行（不用脚本也行）

```bash
# 1. 下载并赋权
scp rust-light-proxy-linux-amd64 user@server:/usr/local/bin/rust-light-proxy
ssh user@server "chmod +x /usr/local/bin/rust-light-proxy"

# 2. 启动 SOCKS5 + 认证（v2 起密码必须走环境变量或文件）
export RLP_PASS='mypassword'
rust-light-proxy serve \
  --listen 0.0.0.0:1080 \
  --user myuser \
  --pass-env RLP_PASS
```

客户端就可以用：

```text
socks5h://myuser:mypassword@<server_ip>:1080
```

或者用配置文件：

```bash
rust-light-proxy -c /etc/rust-light-proxy/config.toml
```

---

## 🎛 命令行参数

```bash
rust-light-proxy --help
rust-light-proxy serve --help
```

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-c, --config <FILE>` | TOML 配置文件路径 | — |
| `serve --listen <ADDR>` | 监听地址 | `0.0.0.0:1080` |
| `serve --mode <MODE>` | 代理模式：`socks5` / `http` / `mixed` | `socks5` |
| `serve --user <USER>` | 代理账号 | — |
| `serve --pass-env <VAR>` | 从指定环境变量读取密码 | — |
| `serve --pass-file <FILE>` | 从指定文件读取密码 | — |
| `serve --max-connections <N>` | 最大并发，`0` = 默认 512 | `0` |
| `serve --bind <DEV\|IP>` | 出口绑定：网口名（仅 Linux）或本地源 IP；留空 = 系统默认路由 | 空 |

> ⚠️ **`--pass` 已禁用**（命令行密码会泄露到 `ps`/`/proc/*/cmdline`），请使用 `--pass-env` 或 `--pass-file`。

---

## 🧰 systemd 部署

最简手动部署（v2 加固版）：

```bash
sudo cp rust-light-proxy-linux-amd64 /usr/local/bin/rust-light-proxy
sudo chmod +x /usr/local/bin/rust-light-proxy

sudo mkdir -p /etc/rust-light-proxy /var/log/rust-light-proxy
sudo tee /etc/rust-light-proxy/config.toml >/dev/null <<'EOF'
[server]
listen = "0.0.0.0:1080"
mode = "socks5"
max_connections = 0          # 0 = 默认 512
connect_timeout_secs = 10
idle_timeout_secs = 300
handshake_timeout_secs = 10
outbound_bind = ""            # 留空 = 默认路由；可填 "eth1" 或源 IP

[auth]
enabled = true
username = "myuser"
password = "mypassword"

[socks5]
enabled = true
remote_dns = true

[http]
enabled = false

[dns]
cache_capacity = 2048
positive_ttl_secs = 300
negative_ttl_secs = 30

[tuning]
buffer_pool_size = 1024
relay_buffer_bytes = 32768

[security]
per_ip_rps = 50
auth_fail_ban_secs = 60

[logging]
level = "warn"
access_log = true
file = "/var/log/rust-light-proxy/access.log"
EOF

sudo tee /etc/systemd/system/rust-light-proxy.service >/dev/null <<'EOF'
[Unit]
Description=Rust Light Proxy
After=network.target

[Service]
Type=simple
DynamicUser=yes
ExecStart=/usr/local/bin/rust-light-proxy -c /etc/rust-light-proxy/config.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
MemoryDenyWriteExecute=yes
ReadWritePaths=/var/log/rust-light-proxy
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now rust-light-proxy
sudo systemctl status rust-light-proxy
```

---

## 🧪 测试

```bash
# SOCKS5H（远程 DNS）
curl -x socks5h://myuser:mypassword@<server_ip>:1080 https://example.com

# HTTP CONNECT
curl -x http://myuser:mypassword@<server_ip>:8080 https://example.com

# 本机自连测试也可以（用公网 IP 或 127.0.0.1）
curl -x socks5h://myuser:mypassword@127.0.0.1:1080 https://www.google.com
```

服务端日志应输出类似：

```text
proto=socks5 target=example.com:443 uploaded=12345 downloaded=67890 duration_ms=1023 status=ok
```

---

## 🛰️ 出口绑定（多网卡 / 多 IP）

很多 VPS 或物理机有多张网卡或多个公网 IP，需要让代理流量从指定网口/IP 出去。

### 在交互菜单中选择

执行「添加实例」时，脚本会自动列出本机所有网口供你选择：

```text
出口绑定（指定走哪个网口/IP 出网）
  本机检测到的网口：
  ──────────────────────────────────────────────
   #   网口名         状态      IPv4               IPv6
  ──────────────────────────────────────────────
   1)  eth0           up        1.2.3.4            -
   2)  eth1           up        5.6.7.8            -
   3)  wg0            unknown   10.0.0.2           -
  ──────────────────────────────────────────────
   0)  默认（不绑定，使用系统路由） ← 推荐
   c)  手动输入网口名或源 IP
```

不同主机网口名不同（`eth0` / `ens18` / `enp3s0` / `wg0` …），脚本会**自动检测**，不需要你记住。

### 配置文件中手动指定

```toml
[server]
# 留空 = 系统默认路由
# 填网口名（仅 Linux，需要 CAP_NET_RAW）
outbound_bind = "eth1"
# 或填本地源 IP
# outbound_bind = "5.6.7.8"
```

### 命令行参数

```bash
rust-light-proxy serve --listen 0.0.0.0:1080 --user u --pass-env P --bind eth1
rust-light-proxy serve --listen 0.0.0.0:1080 --user u --pass-env P --bind 5.6.7.8
```

### 注意事项

- **绑定网口名**：使用 Linux `SO_BINDTODEVICE`，需要 `root` 或 `CAP_NET_RAW` 能力（`install.sh` 创建的 systemd 服务已自动授予）。
- **绑定源 IP**：使用普通 `bind()`，不需要特殊权限，但 IP 必须真实存在于某个本机网卡上。
- **协议族匹配**：绑定 IPv4 源 IP 时只能连 IPv4 目标；IPv6 同理。
- 留空时走系统默认路由（最常见，推荐）。

---

## 🪵 日志大小限制

- **默认上限：500 MB**（强制生效，无需配置）
- 日志路径：`/var/log/rust-light-proxy/<instance>.log`
- 实现机制（双重保险）：
  1. 写入 `logrotate` 配置 `size <N>M` + `copytruncate`（系统有 `logrotate` 时启用）
  2. 写入 `/etc/cron.d/rust-light-proxy-logrotate`，**每分钟**检查一次，超过阈值即 `truncate` 清空
- 超过上限时直接 **清空文件重新写入**（流量统计同时归零）

修改上限（菜单第 8 项）：

```bash
# 交互菜单
sudo bash install.sh    # 选 8

# 非交互一行命令
sudo ACTION=log LOG_LIMIT_MB=200 bash install.sh
```

恢复默认 500 MB：

```bash
sudo ACTION=log LOG_LIMIT_MB=500 bash install.sh
```

---

## ✅ 已实现 / ❌ 暂未实现

<table>
<tr>
<th>✅ v2 已实现</th>
<th>🛣 后续路线</th>
</tr>
<tr>
<td valign="top">

- SOCKS5 TCP CONNECT
- SOCKS5 用户名/密码认证（RFC 1929）
- SOCKS5H 远程 DNS（DOMAIN）+ LRU 缓存
- Happy Eyeballs IPv4/IPv6 双栈竞速
- HTTP CONNECT + Basic 认证
- `mixed` 单端口双协议
- monoio io_uring + splice 零拷贝
- mimalloc 分配器
- 握手 / 连接 / 空闲三段超时
- 最大并发限制 + 每 IP 速率限制
- 认证失败封禁 / slowloris 防护
- 常量时间认证对比（抗时序）
- 出口网口/源 IP 绑定
- TOML 配置 + CLI 参数
- 结构化访问日志

</td>
<td valign="top">

- UDP ASSOCIATE
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
本地 glibc 低于 2.28（CentOS 7 / Ubuntu 16.04 等）。请升级到 Debian 10 / Ubuntu 18.04 / CentOS 8 及以上，或等待 musl 静态版本。
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
检查防火墙（<code>ufw</code> / <code>firewalld</code> / 云厂商安全组）是否放行了监听端口。
</details>

<details>
<summary><b>认证失败</b></summary>
<br/>
客户端 URI 的 <code>user:pass</code> 必须与服务端 <code>--user / --pass-env</code> 或配置文件中的 <code>[auth]</code> 完全一致。注意 v2 起 <code>--pass</code> 已禁用。
</details>

<details>
<summary><b>报错 <code>RLIMIT_NOFILE ... is below required ...</code></b></summary>
<br/>
当前进程 fd 上限太低。systemd 服务已设 <code>LimitNOFILE=1048576</code>；手动运行时执行 <code>ulimit -n 65535</code>，或降低 <code>max_connections</code>。
</details>

<details>
<summary><b>如何校验文件完整性</b></summary>
<br/>

```bash
sha256sum rust-light-proxy-linux-*
```

</details>

---

## 📜 协议

[MIT](LICENSE) © judy-gotv

<p align="center">
  <sub>用 ❤️ 与 🦀 打造</sub>
</p>
