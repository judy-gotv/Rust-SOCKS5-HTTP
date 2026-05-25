<h1 align="center">🚀 MicaProxy <sup><sub>v3.0.6</sub></sup></h1>

<p align="center">
  Lightweight, stable, low-footprint <b>SOCKS5 / SOCKS5 UDP / HTTP / HTTPS</b> proxy<br/>
  <sub>Rust + monoio (epoll / io_uring dual driver) + mimalloc · Cloudflare WARP / kernel WireGuard outbound</sub>
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
  <a href="README.md">中文</a> ·
  <a href="#-one-click-install-recommended">Install</a> ·
  <a href="#-file-list">Files</a> ·
  <a href="#-systemd-deployment">systemd</a> ·
  <a href="#-outbound-profiles">Outbound profiles</a> ·
  <a href="#-faq">FAQ</a>
</p>

---

## ✨ Features (v3.0.6)

- 🪶 **Lightweight** — release binary ~3.5 MB (stripped), idle memory < 20 MB
- ⚡ **Dual monoio driver** — defaults to `epoll` (avoids some Linux 6.1 kernels reporting io_uring idle as `wa` 90%+); switchable to `io_uring`
- 🚀 **mimalloc allocator** — noticeably lower allocation overhead under high-concurrency short-lived connections
- 📦 **Full SOCKS5 suite** — TCP `CONNECT` + **UDP `ASSOCIATE`** (transparent passthrough for QUIC / HTTP/3 / DNS over UDP)
- 🌐 **HTTP / HTTPS** — HTTP `CONNECT` tunneling **plus** plain HTTP `GET http://...` forwarding; auto strips `Proxy-Authorization` / `Proxy-Connection`
- 🛰️ **Named outbound profiles**
  - `default` — system default route
  - `ipv4` — resolve / dial IPv4 only
  - `ipv6` — resolve / dial IPv6 only
  - `wireguard_kernel` — kernel WireGuard interface (**Cloudflare WARP**), SO_MARK + policy routing, **does not hijack** the default route
- 🔐 **Per-listener auth** — independent `username` / `password` per listener, **constant-time** comparison (`subtle`), timing-side-channel resistant
- 🧠 **Smart DNS** — built-in LRU cache + negative cache + in-flight deduplication; configurable `prefer_ipv4`
- 🌍 **Happy Eyeballs (RFC 8305)** — concurrent IPv4 / IPv6 race
- 🛡️ **Security guard** — per-IP rate limiting, auth-failure ban, slowloris protection
- 🧵 **Multi-instance** — systemd template service, N independent accounts/ports on one box
- 📊 **Structured logging** — fields like `uploaded` / `downloaded` / `duration_ms`
- 🪵 **Hard log-size cap** — 500 MB default, customizable from the menu, auto-truncates when exceeded
- 🔒 **systemd hardening** — `MemoryDenyWriteExecute` + `ProtectSystem=strict` + restricted CAPs (keeps `CAP_NET_ADMIN` for WARP/WireGuard)

---

## 📦 One-click install (recommended)

Run directly on your VPS — the script auto-detects the architecture and downloads the matching binary from GitHub Releases:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

> Or via wget:
> ```bash
> wget -qO- https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh | sudo bash
> ```

The interactive menu covers everything:

| # | Action | Description |
|:-:|---|---|
| 1 | Add instance | Protocol (**socks5 / http**), outbound profile (**default / ipv4 / ipv6 / warp**), port, credentials |
| 2 | List instances | Table view: protocol, listen, status, outbound profile |
| 3 | Show connection info | Print each instance's `socks5h://` / `http://` client URI |
| 4-6 | Start / Stop / Restart | Single or all |
| 7 | Traffic stats | Aggregated `uploaded` / `downloaded` + current log size |
| 8 | Delete instance | Cleans up systemd unit and config |
| 9 | Set log-size cap | Default **500 MB**, customizable; auto-truncates when exceeded |
| 10 | Update binary | Pull latest from GitHub Releases and restart instances |
| 11 | Uninstall everything | Services, configs, logs, binary — gone |

Non-interactive quick add for a SOCKS5 instance:

```bash
sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=s5-1 \
     LISTEN_PORT=1080 PROXY_USER=myuser PROXY_PASS=mypass \
     bash <(curl -fsSL https://raw.githubusercontent.com/judy-gotv/Rust-SOCKS5-HTTP/main/install.sh)
```

---

## 📁 File list

| File | Arch | Target |
|---|---|---|
| 🛠 `install.sh` | universal | One-click install/manage script (menu + multi-instance + traffic stats) |
| 💻 `micaproxy-linux-amd64` | `x86_64` | Common VPS / Intel / AMD servers / desktop Linux |
| 📱 `micaproxy-linux-arm64` | `aarch64` | ARM64 servers, Raspberry Pi 4/5, Oracle Ampere, AWS Graviton |
| 🤖 `micaproxy-linux-armv7` | `armv7hf` | Raspberry Pi 2/3, 32-bit ARM routers/boxes |

### 🔍 Picked the wrong one? One line:

```bash
uname -m
```

| `uname -m` output | Choose |
|---|---|
| `x86_64` | `micaproxy-linux-amd64` |
| `aarch64` / `arm64` | `micaproxy-linux-arm64` |
| `armv7l` / `armv7hl` | `micaproxy-linux-armv7` |

---

## 🔧 Build info

<table>
<tr><td><b>Language</b></td><td>Rust (stable, 1.94+)</td></tr>
<tr><td><b>Async runtime</b></td><td>monoio (Linux, <b>epoll default</b> / io_uring optional) + Tokio</td></tr>
<tr><td><b>Allocator</b></td><td>mimalloc</td></tr>
<tr><td><b>Cross-compile</b></td><td>Rust + zig cc (zig 0.13)</td></tr>
<tr><td><b>glibc baseline</b></td><td><b>2.28</b> (Debian 10 / Ubuntu 18.04 / CentOS 8 / RHEL 8+ all compatible)</td></tr>
<tr><td><b>Linking</b></td><td>Dynamically linked glibc (only depends on system libc / pthread / dl)</td></tr>
<tr><td><b>Optimizations</b></td><td><code>opt-level = 3</code> · <code>lto = thin</code> · <code>panic = abort</code> · <code>strip = true</code></td></tr>
</table>

> ⚠️ Minimum glibc raised to **2.28** (due to `statx`).

---

## ⚡ Quick run (no script)

Starting from v3.0.6, MicaProxy **must** be started via a config file (CLI `listen/mode` flags are gone):

```bash
# 1. Install the binary
mkdir -p /opt/MicaProxy
install -m 0755 micaproxy-linux-amd64 /opt/MicaProxy/MicaProxy

# 2. Write a minimal config
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

# 3. Run
/opt/MicaProxy/MicaProxy -c /opt/MicaProxy/config.toml
```

Client URI:

```text
socks5h://myuser:mypassword@<server_ip>:1080
```

---

## 🎛 Command-line flags

v3.0.6 reduces the CLI to a single switch:

| Flag | Description |
|---|---|
| `-c, --config <FILE>` | Path to TOML config file (**required**) |
| `-h, --help` | Help |
| `-V, --version` | Version |

All listeners / outbounds / auth are declared in the config file.

---

## 🧰 systemd deployment

Template unit (auto-generated by `install.sh`):

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

Start / stop any instance:

```bash
sudo systemctl enable --now MicaProxy@s5-1.service
sudo systemctl status      MicaProxy@s5-1.service
sudo systemctl stop        MicaProxy@s5-1.service
```

> ⚠️ `ProtectKernelTunables=no` — introduced by the v3.0.6 WARP fix: MicaProxy needs to write `net.ipv4.conf.*.{src_valid_mark,rp_filter}` sysctls when bringing up a WireGuard outbound. Plain SOCKS5/HTTP doesn't touch any sysctl.

---

## 🧪 Testing

```bash
# SOCKS5H (remote DNS)
curl -x socks5h://myuser:mypassword@<server_ip>:1080 https://example.com

# HTTP CONNECT
curl -x http://myuser:mypassword@<server_ip>:8080 https://example.com

# Plain HTTP forwarding
curl -x http://myuser:mypassword@<server_ip>:8080 http://example.com

# SOCKS5 UDP (QUIC / HTTP/3 site)
curl --http3 -x socks5h://myuser:mypassword@<server_ip>:1080 https://cloudflare-quic.com
```

Server-side log line looks like:

```text
proto=socks5 target=example.com:443 uploaded=12345 downloaded=67890 duration_ms=1023 status=ok
```

---

## 🛰️ Outbound profiles

v3 introduced **named outbound profiles** so different listeners can take entirely different egress paths inside one process:

| profile | type | description |
|---|---|---|
| `default` | system default route | normal use |
| `ipv4` | IPv4-only | DNS resolves A only, dials IPv4 only |
| `ipv6` | IPv6-only | DNS resolves AAAA only, dials IPv6 only |
| `wireguard_kernel` | Linux kernel WireGuard | Cloudflare WARP / self-hosted WG, **SO_MARK + policy routing**, does **not** hijack the default route |

### Protocol semantics (simplified after v3.0.2)

| Protocol | Client target | DNS resolver |
|---|---|---|
| `socks5` | IP **or** domain (auto-detect via ATYP) | When ATYP=DOMAIN the **proxy** resolves it (subject to outbound profile) |
| `http`   | HTTP CONNECT or plain HTTP             | **Proxy** |

> ✨ Since v3.0.2 `socks5h` has been merged into `socks5` — clients work whether they send an IP or a domain. To make the proxy resolve DNS (recommended), have the client use `socks5h://...`.

### Cloudflare WARP one-shot

```bash
# Interactive menu: Add instance → protocol 1 (SOCKS5) → outbound profile 4 (warp)
sudo bash install.sh

# Non-interactive (after registering WARP and getting the private/peer pubkey):
sudo ACTION=add PROXY_TYPE=socks5 INSTANCE_NAME=warp-1 \
     LISTEN_PORT=1089 PROXY_USER=u PROXY_PASS=p \
     OUTBOUND_PROFILE=warp \
     WG_PRIVATE_KEY='your WG private key' \
     WG_PEER_PUBLIC_KEY='WARP peer public key' \
     bash install.sh
```

The WARP profile picks its egress path via **SO_MARK + policy routing table**, leaving the main default route untouched — other instances are completely unaffected.

WARP UDP defaults to preferring IPv6 (`udp_prefer_ipv6 = true`) to avoid dead UDP-IPv4 paths on some WARP endpoints.

---

## 🪵 Log-size cap

- **Default cap: 500 MB** (enforced unconditionally, no config required)
- Log path: `/opt/MicaProxy/log/<instance>.log`
- Belt-and-suspenders enforcement:
  1. `logrotate` config with `size <N>M` + `copytruncate` (if the system has `logrotate`)
  2. `/etc/cron.d/MicaProxy-logrotate` — checks **every minute** and `truncate`s when exceeded
- On overflow the file is **truncated and re-started from zero** (traffic counters reset too)

Change the cap (menu item 9):

```bash
# Interactive
sudo bash install.sh    # pick 9

# One-liner
sudo ACTION=log LOG_LIMIT_MB=200 bash install.sh
```

---

## ✅ Implemented / ❌ Not yet

<table>
<tr>
<th>✅ v3.0.6 implemented</th>
<th>🛣 Roadmap</th>
</tr>
<tr>
<td valign="top">

- SOCKS5 TCP `CONNECT` (auto-detects IP / domain)
- **SOCKS5 UDP `ASSOCIATE`** (QUIC / HTTP/3 / DNS)
- SOCKS5 username/password auth (RFC 1929)
- HTTP `CONNECT` + plain HTTP forwarding (Basic auth)
- Multi-listener with independent creds / protocol / outbound
- Named outbound profiles: default / ipv4 / ipv6 / wireguard_kernel
- **Cloudflare WARP egress** (TCP + UDP, SO_MARK + policy routing)
- Dual monoio driver (epoll default / io_uring optional)
- mimalloc allocator
- DNS LRU + negative cache + in-flight dedup
- Happy Eyeballs IPv4/IPv6 race
- Three-stage handshake / connect / idle timeouts
- Max concurrency + per-IP rate limit
- Auth-fail ban / slowloris protection
- Constant-time auth compare (timing-safe)
- Structured access log + UDP metrics

</td>
<td valign="top">

- HTTP/3 MASQUE / CONNECT-UDP
- Prometheus metrics (partial)
- ACL / port blacklists
- Hot config reload
- Web admin UI
- musl static build

</td>
</tr>
</table>

---

## ❓ FAQ

<details>
<summary><b>Startup error: <code>GLIBC_2.28 not found</code></b></summary>
<br/>
Your glibc is older than 2.28 (CentOS 7 / Ubuntu 16.04 etc.). Upgrade to Debian 10 / Ubuntu 18.04 / CentOS 8 or later.
</details>

<details>
<summary><b><code>top</code> / <code>vmstat</code> shows <code>wa</code> at 90%+</b></summary>
<br/>

Some Linux 6.1 kernels account io_uring idle waits as iowait. v3.0.3 changed the default driver to <code>epoll</code>, so you shouldn't see this anymore. If you explicitly switched to io_uring and hit it, revert with:

```toml
[runtime]
driver = "epoll"
```

</details>

<details>
<summary><b>Normal listeners stall after configuring WARP</b></summary>
<br/>
Fixed in v3.0.6: WARP outbound TCP fds now have <code>O_NONBLOCK</code> enforced so they can no longer block other listeners on the same monoio thread. Make sure you're on v3.0.6+.
</details>

<details>
<summary><b><code>address already in use</code></b></summary>
<br/>

Pick a different port, or find the offender:

```bash
ss -lntp | grep 1080
```

</details>

<details>
<summary><b>Client can't connect</b></summary>
<br/>
Check the firewall (<code>ufw</code> / <code>firewalld</code> / cloud-provider security group) is allowing the listening port. SOCKS5 UDP also needs the same port open for UDP.
</details>

<details>
<summary><b>Auth fails</b></summary>
<br/>
Since v3.0.2 auth fields live <b>inside each listener</b> (the global <code>[auth]</code> section is gone):
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
<summary><b>Verify file integrity</b></summary>
<br/>

```bash
sha256sum micaproxy-linux-*
```

</details>

---

## 📜 License

[MIT](LICENSE) © judy-gotv

<p align="center">
  <sub>Built with ❤️ and 🦀</sub>
</p>
