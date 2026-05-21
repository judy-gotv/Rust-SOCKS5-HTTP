# Rust Light Proxy说明

本目录包含已交叉编译完成的 Linux 二进制文件以及一键安装管理脚本。

## 一键安装（推荐）

直接在 VPS 上运行，脚本会自动识别架构并从 GitHub Releases 下载对应二进制：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

或者：

```bash
wget -qO- https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh | sudo bash
```

进入交互菜单后可：

- 添加 SOCKS5 / HTTP CONNECT 实例
- 自定义端口、账号、密码、最大并发
- 启动 / 停止 / 重启 / 删除任意实例
- 查看实例流量统计（基于 access log 累计）
- 更新二进制（自动重启所有实例）
- 一键卸载并清理

非交互式快速安装一个 SOCKS5 实例：

```bash
sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=socks5-1 \
     LISTEN_PORT=1080 PROXY_USER=myuser PROXY_PASS=mypass \
     bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

## 文件清单

| 文件 | 目标架构 | 适用平台 |
|---|---|---|
| `install.sh` | 通用 | 一键安装管理脚本（带菜单 + 流量统计 + 多实例） |
| `rust-light-proxy-linux-amd64` | x86_64 | 常见 VPS、Intel/AMD 服务器、桌面 Linux |
| `rust-light-proxy-linux-arm64` | aarch64 | ARM64 服务器、树莓派 4/5（64 位系统）、Oracle Cloud Ampere、AWS Graviton |
| `rust-light-proxy-linux-armv7` | ARMv7 hardfloat | 树莓派 2/3、各类 32 位 ARM 路由器/盒子 |

## 构建信息

- 语言：Rust（stable，windows-gnu 工具链 + zig cc 作为交叉链接器）
- glibc 基线：**2.17**（兼容 CentOS 7 / Debian 8 / Ubuntu 14.04 及之后的所有主流发行版）
- 链接方式：动态链接 glibc（仅依赖系统 libc / libpthread / libdl 等基础库）
- 已 strip（不含调试符号）
- 已开启 LTO、`panic=abort`、`codegen-units = 1`

## 如何确认架构

在目标服务器上执行：

```bash
uname -m
```

| `uname -m` 输出 | 选择文件 |
|---|---|
| `x86_64` | `rust-light-proxy-linux-amd64` |
| `aarch64` / `arm64` | `rust-light-proxy-linux-arm64` |
| `armv7l` / `armv7hl` | `rust-light-proxy-linux-armv7` |

## 快速运行

```bash
# 1. 上传到服务器
scp rust-light-proxy-linux-amd64 user@server:/usr/local/bin/rust-light-proxy

# 2. 赋予执行权限
ssh user@server "chmod +x /usr/local/bin/rust-light-proxy"

# 3. 启动（SOCKS5 + 用户名密码认证）
/usr/local/bin/rust-light-proxy serve \
  --listen 0.0.0.0:1080 \
  --user myuser \
  --pass mypassword
```

启动后客户端就可以用：

```text
socks5h://myuser:mypassword@<server_ip>:1080
```

## 使用配置文件

```bash
/usr/local/bin/rust-light-proxy -c /etc/rust-light-proxy/config.toml
```

配置文件示例见项目根目录的 `config.example.toml`。

## 命令行参数

```bash
rust-light-proxy --help
rust-light-proxy serve --help
```

主要参数：

| 参数 | 说明 | 默认值 |
|---|---|---|
| `-c, --config <FILE>` | TOML 配置文件路径 | 无 |
| `serve --listen <ADDR>` | 监听地址 | `0.0.0.0:1080` |
| `serve --mode <MODE>` | 代理模式：`socks5` / `http` / `mixed` | `socks5` |
| `serve --user <USER>` | 代理账号 | 无 |
| `serve --pass <PASS>` | 代理密码 | 无 |
| `serve --max-connections <N>` | 最大并发，`0` 表示不限制 | `0` |

`--user` 与 `--pass` 都提供时启用认证，否则免认证。

## 部署到 systemd

参考项目根目录 `deploy/rust-light-proxy.service`（单实例）和 `deploy/rust-light-proxy@.service`（多实例模板），或直接使用 `install.sh` 一键安装脚本。

简易部署：

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
User=nobody
Group=nogroup
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

## 测试

```bash
# 正常请求
curl -x socks5h://myuser:mypassword@<server_ip>:1080 https://example.com

# HTTP CONNECT 模式（启动时设置 --mode http 或 --mode mixed）
curl -x http://myuser:mypassword@<server_ip>:8080 https://example.com
```

## 已实现功能（第一版）

- SOCKS5 TCP CONNECT
- SOCKS5 username/password 认证（RFC 1929）
- SOCKS5H 远程 DNS（DOMAIN 地址类型）
- IPv4 / IPv6 / DOMAIN 全支持
- HTTP CONNECT 隧道 + Basic 认证（`Proxy-Authorization`）
- `mixed` 模式：单端口同时识别 SOCKS5 和 HTTP CONNECT
- 双向 TCP 转发（`copy_bidirectional`）+ 字节统计
- 握手 / 连接 / 空闲三段超时
- 最大并发连接限制（默认 `0` 不限制）
- TOML 配置文件 + 命令行参数
- 结构化访问日志（包含 `uploaded` / `downloaded` / `duration_ms`）

## 暂未实现（按需可后续添加）

- UDP ASSOCIATE
- Prometheus metrics
- ACL / 端口黑名单
- DNS 缓存
- 配置热重载

## 故障排查

- **启动报 `glibc not found` / 版本过低**：本地 glibc 低于 2.17，请升级系统或使用 musl 静态构建版本。
- **`address already in use`**：换端口，或 `ss -lntp | grep 1080` 找占用进程。
- **客户端连接被拒**：检查防火墙（`ufw` / `firewalld` / 云厂商安全组）是否放行了监听端口。
- **认证失败**：客户端 URI 的 `user:pass` 必须与服务端 `--user/--pass` 或配置文件中的 `[auth]` 完全一致。

## 文件校验

可在上传前生成 SHA256 以便核对：

```bash
sha256sum rust-light-proxy-linux-*
```
