# wstunnel Docker Server

A minimal Docker image for [wstunnel](https://github.com/erebe/wstunnel) server-side deployment, designed to work behind an nginx reverse proxy.

Wstunnel tunnels TCP traffic over WebSocket (or HTTP/2), allowing you to bypass firewalls and DPI by wrapping connections in standard HTTPS traffic.

## Table of Contents

- [Use Case](#use-case)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Server Side](#server-side)
- [Nginx Configuration](#nginx-configuration)
- [Client Side](#client-side)
- [Security Considerations](#security-considerations)

---

## Use Case

This setup enables SSH access to a remote server through HTTPS port 443, useful when:

- Direct SSH (port 22) is blocked by a firewall or corporate proxy
- You need to reach a server that only exposes port 443 to the internet
- You want to tunnel SSH over an existing nginx reverse proxy

```
[your machine]
    wstunnel client (local :2222)
        │
        │ wss:// (port 443)
        ▼
[nginx reverse proxy]
    location /wstunnel → proxy_pass :8080
        │
        │ ws:// (port 8080, internal)
        ▼
[wstunnel server container]
        │
        │ TCP (restricted to)
        ▼
[sshd :22 on host]
```

---

## Quick Start

```bash
# Build
docker build -t wstunnel-server:latest .

# Run
docker run -d \
  --name wstunnel \
  --restart unless-stopped \
  -p 8080:8080 \
  wstunnel-server:latest \
  server ws://0.0.0.0:8080 \
  --restrict-to 127.0.0.1:22 \
  --http-upgrade-credentials myuser:mypassword
```

---

## Server Side

### Dockerfile

The image is based on `alpine:3.23` and downloads the official static binary from the wstunnel GitHub releases. The `WSTUNNEL_VERSION` build argument allows pinning to a specific release.

```dockerfile
FROM alpine:3.23

ARG WSTUNNEL_VERSION=10.5.5
ARG TARGETARCH

RUN apk add --no-cache ca-certificates tar && \
    case "${TARGETARCH}" in \
      amd64) ARCH="amd64" ;; \
      arm64) ARCH="arm64" ;; \
      arm)   ARCH="armv7" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    wget -qO /tmp/wstunnel.tar.gz \
      "https://github.com/erebe/wstunnel/releases/download/v${WSTUNNEL_VERSION}/wstunnel_${WSTUNNEL_VERSION}_linux_${ARCH}.tar.gz" && \
    tar -xzf /tmp/wstunnel.tar.gz -C /usr/local/bin wstunnel && \
    chmod +x /usr/local/bin/wstunnel && \
    rm /tmp/wstunnel.tar.gz

EXPOSE 8080

ENTRYPOINT ["wstunnel"]
```

`ENTRYPOINT` is set to `wstunnel` only, with no `CMD`. All arguments are passed explicitly at runtime, giving full flexibility.

### docker-compose.yml

```yaml
services:
  wstunnel:
    image: wstunnel-server:latest
    restart: unless-stopped
    ports:
      - "8080:8080"
    command:
      - server
      - "ws://0.0.0.0:8080"
      - --restrict-to
      - "127.0.0.1:22"
      - --http-upgrade-credentials
      - "myuser:mypassword"
```

> Port 8080 should **not** be exposed directly to the internet. nginx sits in front and handles TLS termination.

### Multi-arch build

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t wstunnel-server:latest .
```

---

## Nginx Configuration

### Key points

- nginx handles TLS termination (Let's Encrypt or your own certificate).
- wstunnel server listens on plain `ws://` internally.
- The `location ^~ /wstunnel` block must be declared **before** any catch-all location to ensure correct routing priority.
- `proxy_buffering off` is required for WebSocket streaming.

```nginx
server {
    listen 443 ssl;
    server_name your-server.example.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    # wstunnel: declared before any catch-all location
    location ^~ /wstunnel {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    location / {
        # your existing config
    }
}
```

The `^~` prefix modifier ensures this location takes precedence over regex-based locations that might otherwise capture the path first.

> **Note**: if nginx is running in Docker, use the container's IP or Docker network hostname instead of `127.0.0.1` in `proxy_pass`.

---

## Client Side

Install wstunnel on your local machine from the [releases page](https://github.com/erebe/wstunnel/releases).

### Basic usage

```bash
# Start the tunnel (forwards local :2222 → remote sshd :22)
wstunnel client \
  -L tcp://2222:127.0.0.1:22 \
  -P wstunnel \
  wss://your-server.example.com:443

# Connect via SSH through the tunnel
ssh user@localhost -p 2222
```

### With credentials

If `--http-upgrade-credentials` is enabled on the server:

```bash
wstunnel client \
  -L tcp://2222:127.0.0.1:22 \
  -P wstunnel \
  --http-upgrade-credentials myuser:mypassword \
  wss://your-server.example.com:443
```

### Parameters explained

| Parameter | Description |
|-----------|-------------|
| `-L tcp://2222:127.0.0.1:22` | Listen on local port 2222, forward to remote `127.0.0.1:22` |
| `-P wstunnel` | HTTP upgrade path prefix — must match the nginx `location` path |
| `--http-upgrade-credentials` | Basic auth credentials sent during WebSocket upgrade |
| `-p http://[user:pass@]host:port` | Route the connection through a corporate HTTP proxy |
| `wss://` | Use WebSocket over TLS (always use `wss://` when nginx handles TLS) |

> **Important**: the server URL must not include a path (`wss://host:443`, not `wss://host:443/wstunnel/`). The path is controlled exclusively by `-P`.

### Behind a corporate HTTP proxy

In corporate environments, outbound connections are often forced through an HTTP proxy. wstunnel supports this natively via the `-p` flag (or the `HTTP_PROXY` environment variable).

```bash
# Proxy without authentication
wstunnel client \
  -L tcp://2222:127.0.0.1:22 \
  -P wstunnel \
  -p http://proxy.corp.example.com:8080 \
  wss://your-server.example.com:443

# Proxy with authentication
wstunnel client \
  -L tcp://2222:127.0.0.1:22 \
  -P wstunnel \
  -p http://proxyuser:proxypassword@proxy.corp.example.com:8080 \
  wss://your-server.example.com:443
```

Alternatively, export the proxy via environment variable (useful in scripts or shell profiles):

```bash
export HTTP_PROXY=http://proxyuser:proxypassword@proxy.corp.example.com:8080

wstunnel client \
  -L tcp://2222:127.0.0.1:22 \
  -P wstunnel \
  wss://your-server.example.com:443
```

If the proxy credentials contain special characters, percent-encode them in the URL (e.g. `@` → `%40`, `#` → `%23`).

> **Note**: wstunnel connects to the corporate proxy using the HTTP `CONNECT` method, which most proxies support for HTTPS tunneling. The WebSocket upgrade then happens inside that tunnel, so the proxy only sees a standard HTTPS connection to port 443.

### SSH ProxyCommand (no local port)

Alternatively, use wstunnel as an SSH `ProxyCommand` to avoid opening a local port:

```
# ~/.ssh/config
Host myserver-tunnel
    HostName your-server.example.com
    User ubuntu
    ProxyCommand wstunnel client --log-lvl=off \
      -L "stdio://127.0.0.1:22" \
      -P wstunnel \
      wss://your-server.example.com:443

# Same, behind a corporate proxy
Host myserver-tunnel-corp
    HostName your-server.example.com
    User ubuntu
    ProxyCommand wstunnel client --log-lvl=off \
      -L "stdio://127.0.0.1:22" \
      -P wstunnel \
      -p http://proxyuser:proxypassword@proxy.corp.example.com:8080 \
      wss://your-server.example.com:443
```

Then simply:

```bash
ssh myserver-tunnel
```

---

## Security Considerations

### What is exposed

With `--restrict-to 127.0.0.1:22`, wstunnel can only forward connections to SSH on localhost. An attacker who successfully establishes a tunnel can only attempt SSH authentication — nothing else is reachable.

### Threat model summary

| Risk | Severity | Mitigation |
|------|----------|------------|
| Unauthenticated access to `/wstunnel` path | Medium | Enable `--http-upgrade-credentials` |
| Brute-force SSH through tunnel | Medium | Keys only (`PasswordAuthentication no`), fail2ban/crowdsec |
| Unrestricted tunnel if `--restrict-to` is removed | High | Always set `--restrict-to` in production |
| Outdated wstunnel binary with CVEs | Low–Medium | Pin version, monitor releases |

### Recommendations

**Enforce SSH hardening** — this is the last line of defence once the tunnel is established:

```
# /etc/ssh/sshd_config
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
```

**Use `--http-upgrade-credentials`** on both server and client. The credentials travel in the HTTP `Authorization` header during the WebSocket upgrade and are validated by wstunnel itself, independently of nginx.

**Do not expose port 8080** to the internet. The wstunnel container should only be reachable through nginx on the Docker internal network.

**Monitor releases** at [github.com/erebe/wstunnel/releases](https://github.com/erebe/wstunnel/releases) and rebuild the image when new versions are available. Since the binary is downloaded at build time, updates require a rebuild — this is intentional and avoids unexpected changes from auto-updates.

---

## References

- [wstunnel upstream repository](https://github.com/erebe/wstunnel)
- [wstunnel releases](https://github.com/erebe/wstunnel/releases)
