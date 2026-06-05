# kryptlink — Hostinger VPS deploy guide

Target: serve `kry.li` (and `www.kry.li`) from a Hostinger Linux VPS.
Pure Krypton, no PHP, no Apache, no Node. The VPS runs:

  - **kryptlink** (single binary) listening on `127.0.0.1:8080`
  - **nginx** terminating HTTPS on `:443` and proxying to `:8080`
  - **certbot** auto-renewing Let's Encrypt TLS cert
  - **sqlite3** holding `links` + `clicks` tables

## 1. Provision the VPS

Hostinger VPS plan (KVM 1 is plenty: 1 vCPU / 4 GB / 50 GB SSD).
Ubuntu 22.04 LTS. SSH key login.

## 2. Point DNS at the VPS

In Hostinger's DNS for `kry.li`:

  Type   Name   Value                TTL
  A      @      <VPS IPv4>           1h
  A      www    <VPS IPv4>           1h
  AAAA   @      <VPS IPv6 if any>    1h
  AAAA   www    <VPS IPv6 if any>    1h

Wait until `dig kry.li +short` returns the VPS IP from your laptop.

## 3. One-shot install on the VPS

SSH in as root or a sudoer:

```bash
apt update && apt install -y git sqlite3 nginx certbot python3-certbot-nginx
# Krypton: clone + bootstrap a Linux kcc
git clone https://github.com/t3m3d/krypton.git /opt/krypton
cd /opt/krypton
./scripts/install_linux.sh        # builds kcc-x64 from bootstrap seeds
ln -s /opt/krypton/compiler/linux_x86/kcc-x64 /usr/local/bin/kcc

# kryptlink: build + initialise
mkdir -p /opt/kryptlink/public
cp /opt/krypton/kryptlink/public/index.html /opt/kryptlink/public/
sqlite3 /opt/kryptlink/kryptlink.db < /opt/krypton/kryptlink/schema.sql
kcc -o /opt/kryptlink/kryptlink /opt/krypton/kryptlink/run.k
```

## 4. systemd service

`/etc/systemd/system/kryptlink.service`:

```ini
[Unit]
Description=kryptlink URL shortener
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/kryptlink
ExecStart=/opt/kryptlink/kryptlink 8080
Restart=on-failure
Environment="KRYPTLINK_PASSWORD=CHANGE_ME_TO_SOMETHING_LONG"
Environment="KRYPTLINK_DB=/opt/kryptlink/kryptlink.db"
Environment="KRYPTLINK_PUBLIC_HOST=https://www.kry.li"
Environment="KRYPTLINK_PUBLIC_DIR=/opt/kryptlink/public"

[Install]
WantedBy=multi-user.target
```

Then:

```bash
chown -R www-data:www-data /opt/kryptlink
systemctl daemon-reload
systemctl enable --now kryptlink
systemctl status kryptlink     # should be "active (running)"
```

## 5. nginx reverse proxy

`/etc/nginx/sites-available/kry.li`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name kry.li www.kry.li;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable + test:

```bash
ln -s /etc/nginx/sites-available/kry.li /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx
```

## 6. Let's Encrypt cert

```bash
certbot --nginx -d kry.li -d www.kry.li --redirect --agree-tos -m you@example.com
```

certbot updates the nginx config in place to add the `:443` block and
HTTP-to-HTTPS redirect, then schedules auto-renewal.

## 7. Capture the real client IP

By default kryptlink logs an empty IP. Update `run.k`'s click insert
to honour `X-Forwarded-For` from the nginx proxy (already noted as a
1-line TODO). After editing, rebuild + `systemctl restart kryptlink`.

## 8. Test

  curl https://www.kry.li/                  # landing page
  curl -i https://www.kry.li/admin          # login form
  curl -X POST -d 'password=...' https://www.kry.li/login -c /tmp/c
  curl -b /tmp/c -X POST \
    -d 'url=https://example.com&code=hello' \
    https://www.kry.li/create
  curl -i https://www.kry.li/hello          # 302 → example.com
  curl https://www.kry.li/qr/hello.svg | head -c 80   # SVG
  sqlite3 /opt/kryptlink/kryptlink.db 'SELECT * FROM clicks'

Phone-scan the QR — if it decodes to https://www.kry.li/hello, ship
it. If not, kryptlink's QR mask 0 needs the penalty-driven mask
selector enabled (`stdlib/qr.k` TODO).

## Rotating / updating

```bash
cd /opt/krypton && git pull
kcc -o /opt/kryptlink/kryptlink /opt/krypton/kryptlink/run.k
systemctl restart kryptlink
```

The SQLite DB is preserved across redeploys.

## Backup

  rsync -avz /opt/kryptlink/kryptlink.db backup-host:/path/

(Or set up a daily cron with sqlite3's `.backup` command for a
consistent snapshot during writes.)
