<h1 align="center">🚀 Rust Light Proxy</h1>

<p align="center">
  轻量、稳定、低占用的 <b>SOCKS5 / SOCKS5H / HTTP CONNECT</b> 代理服务<br/>
  <sub>用 Rust + Tokio 写的，单二进制，开箱即用</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/language-Rust-orange?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/runtime-Tokio-blue" alt="Tokio">
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7-success" alt="Arch">
  <img src="https://img.shields.io/badge/glibc-%E2%89%A5%202.17-lightgrey" alt="glibc">
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

## ✨ 特性

- 🪶 **轻量** — Release 二进制 ~1.7 MB，空闲内存 < 20 MB
- ⚡ **高性能** — 基于 Tokio + `copy_bidirectional`，零拷贝转发
- 🔐 **完整认证** — SOCKS5 用户名/密码、HTTP Basic
- 🌐 **SOCKS5H 远程 DNS** — DOMAIN 地址在服务端解析
- 🧩 **三协议合一** — `socks5` / `http` / `mixed`（单端口自动识别）
- 🧵 **多实例** — systemd 模板服务，一台机器跑 N 个独立账号/端口
- 📊 **结构化日志** — 含 `uploaded` / `downloaded` / `duration_ms` 字段
- 🛡️ **资源可控** — 握手 / 连接 / 空闲三段超时，最大并发限制

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
| 1 | 添加实例 | 选择协议、端口、账号密码、并发上限 |
| 2 | 查看实例列表 | 表格显示协议、监听、运行状态 |
| 3-5 | 启动 / 停止 / 重启 | 单个或全部 |
| 6 | 查看流量 | 从 journalctl 累计 `uploaded` / `downloaded` |
| 7 | 删除实例 | 同时清理 systemd 服务和配置 |
| 8 | 更新二进制 | 从 GitHub Releases 拉取最新版并重启实例 |
| 9 | 卸载全部 | 服务、配置、二进制一键清理 |

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
<tr><td><b>语言</b></td><td>Rust（stable）</td></tr>
<tr><td><b>异步运行时</b></td><td>Tokio multi-thread</td></tr>
<tr><td><b>交叉编译</b></td><td>Rust + zig cc</td></tr>
<tr><td><b>glibc 基线</b></td><td>2.17（CentOS 7 / Debian 8 / Ubuntu 14.04 及以上全部兼容）</td></tr>
<tr><td><b>链接方式</b></td><td>动态链接 glibc（仅依赖系统 libc / pthread / dl）</td></tr>
<tr><td><b>优化选项</b></td><td><code>opt-level = 3</code> · <code>lto = thin</code> · <code>panic = abort</code> · <code>strip = true</code></td></tr>
</table>

---

## ⚡ 快速运行（不用脚本也行）

```bash
# 1. 下载并赋权
scp rust-light-proxy-linux-amd64 user@server:/usr/local/bin/rust-light-proxy
ssh user@server "chmod +x /usr/local/bin/rust-light-proxy"

# 2. 启动 SOCKS5 + 认证
rust-light-proxy serve \
  --listen 0.0.0.0:1080 \
  --user myuser \
  --pass mypassword
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
| `serve --pass <PASS>` | 代理密码 | — |
| `serve --max-connections <N>` | 最大并发，`0` 表示不限制 | `0` |

> 💡 `--user` 与 `--pass` 都提供时启用认证，否则免认证。

---

## 🧰 systemd 部署

最简手动部署：

```bash
sudo cp rust-light-proxy-linux-amd64 /usr/local/bin/rust-light-proxy
sudo chmod +x /usr/local/bin/rust-light-proxy

sudo mkdir -p /etc/rust-light-proxy
sudo tee /etc/rust-light-proxy/config.toml >/dev/null <<'EOF'
[server]
listen = "0.0.0.0:1080"
mode = "socks5"
max_connections = 0
connect_timeout_secs = 10
idle_timeout_secs = 300
handshake_timeout_secs = 10

[auth]
enabled = true
username = "myuser"
password = "mypassword"

[socks5]
enabled = true
remote_dns = true

[logging]
level = "info"
access_log = true
EOF

sudo tee /etc/systemd/system/rust-light-proxy.service >/dev/null <<'EOF'
[Unit]
Description=Rust Light Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/rust-light-proxy -c /etc/rust-light-proxy/config.toml
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
```

服务端日志应输出类似：

```text
proto=socks5 target=example.com:443 uploaded=12345 downloaded=67890 duration_ms=1023 status=ok
```

---

## ✅ 已实现 / ❌ 暂未实现

<table>
<tr>
<th>✅ 已实现（第一版）</th>
<th>🛣 后续路线</th>
</tr>
<tr>
<td valign="top">

- SOCKS5 TCP CONNECT
- SOCKS5 用户名/密码认证（RFC 1929）
- SOCKS5H 远程 DNS（DOMAIN）
- IPv4 / IPv6 / DOMAIN
- HTTP CONNECT + Basic 认证
- `mixed` 单端口双协议
- TCP 双向转发 + 字节统计
- 握手 / 连接 / 空闲三段超时
- 最大并发限制
- TOML 配置 + CLI 参数
- 结构化访问日志

</td>
<td valign="top">

- UDP ASSOCIATE
- Prometheus metrics
- ACL / 端口黑名单
- DNS 缓存
- 配置热重载
- 流量上报 / Web 管理

</td>
</tr>
</table>

---

## ❓ 常见问题

<details>
<summary><b>启动报 <code>glibc not found</code> 或版本过低</b></summary>
<br/>
本地 glibc 低于 2.17，请升级系统，或后续切换到 musl 静态构建版本。
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
客户端 URI 的 <code>user:pass</code> 必须与服务端 <code>--user/--pass</code> 或配置文件中的 <code>[auth]</code> 完全一致。
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
