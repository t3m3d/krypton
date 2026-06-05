# kryptlink-node — Hostinger VPS deploy

Production stack: Node.js 22+, built-in SQLite, nginx, Let's Encrypt.
Target: `kry.li` + `www.kry.li`.

## 1. Provision

  - Hostinger VPS (KVM 1 is plenty: 1 vCPU / 4 GB / 50 GB SSD)
  - Ubuntu 22.04 LTS
  - SSH key login

## 2. DNS

In Hostinger DNS for `kry.li`:

    A     @     <VPS IPv4>
    A     www   <VPS IPv4>
    AAAA  @     <VPS IPv6 if any>
    AAAA  www   <VPS IPv6 if any>

Wait until `dig kry.li +short` returns the VPS IP.

## 3. Install Node.js + system bits

```bash
# As root or sudoer:
apt update
apt install -y curl nginx certbot python3-certbot-nginx

# Node.js 22 LTS via NodeSource
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs

node --version    # → v22.x or higher (built-in node:sqlite)
```

## 4. App install

```bash
mkdir -p /opt/kryptlink
cd /opt/kryptlink
git clone --depth 1 https://github.com/t3m3d/krypton.git krypton-src
cp -r krypton-src/kryptlink-node/* .
rm -rf krypton-src
npm install --omit=dev --no-audit --no-fund

# Initialise the DB
node init-db.js /opt/kryptlink/kryptlink.db
chown -R www-data:www-data /opt/kryptlink
```

## 5. systemd service

`/etc/systemd/system/kryptlink.service`:

```ini
[Unit]
Description=kryptlink URL shortener (Node)
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/kryptlink
ExecStart=/usr/bin/node /opt/kryptlink/server.js
Restart=on-failure
Environment="NODE_ENV=production"
Environment="PORT=8080"
Environment="KRYPTLINK_PASSWORD=CHANGE_ME_TO_A_LONG_RANDOM_STRING"
Environment="KRYPTLINK_DB=/opt/kryptlink/kryptlink.db"
Environment="KRYPTLINK_PUBLIC_HOST=https://www.kry.li"
Environment="KRYPTLINK_PUBLIC_DIR=/opt/kryptlink/public"

[Install]
WantedBy=multi-user.target
```

Then:

```bash
systemctl daemon-reload
systemctl enable --now kryptlink
systemctl status kryptlink         # should be "active (running)"
journalctl -u kryptlink -n 50      # logs
```

## 6. nginx reverse proxy

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

Enable + reload:

```bash
ln -s /etc/nginx/sites-available/kry.li /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
```

## 7. Let's Encrypt cert

```bash
certbot --nginx -d kry.li -d www.kry.li --redirect --agree-tos -m you@example.com
```

certbot edits the nginx config in place (adds `:443` block + HTTP-to-HTTPS
redirect) and schedules auto-renewal via systemd timer.

## 8. Verify

    curl -sI https://www.kry.li/                  # 200, landing page
    curl -sI https://www.kry.li/admin             # 200, login form

Log into the admin UI in a browser, create a test link, scan its QR.

## Upgrades

```bash
cd /opt/kryptlink
git -C krypton-src pull --depth 1 || (rm -rf krypton-src && git clone --depth 1 https://github.com/t3m3d/krypton.git krypton-src)
cp krypton-src/kryptlink-node/server.js .
cp krypton-src/kryptlink-node/schema.sql .
npm install --omit=dev --no-audit --no-fund
systemctl restart kryptlink
```

SQLite DB is preserved across redeploys (and the schema CREATEs are
idempotent).

## Backups

Live snapshot:

```bash
sqlite3 /opt/kryptlink/kryptlink.db ".backup /backup/kryptlink-$(date +%F).db"
```

Add to cron for daily backups:

```cron
0 4 * * * sqlite3 /opt/kryptlink/kryptlink.db ".backup /backup/kryptlink-$(date +\%F).db"
```

## Notes

  - `node:sqlite` (built-in, no `better-sqlite3` native build) needs
    **Node 22+**. The systemd unit uses `/usr/bin/node` so make sure
    the NodeSource install is what's on PATH.
  - The server trusts `X-Forwarded-For` headers (`app.set("trust proxy", true)`)
    so `req.ip` reflects the real client IP from nginx.
  - QR codes use M-level error correction by default; bump to "Q" or
    "H" in `server.js` if you expect prints/photos to be damaged.
