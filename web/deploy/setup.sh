#!/usr/bin/env bash
# setup.sh — one-shot setup for krypton-lang.org on a dedicated Linux server
# Run as root: sudo bash setup.sh
#
# What this does:
#   1. Installs dependencies (gcc, nginx, certbot)
#   2. Clones and builds Krypton
#   3. Builds site.htk
#   4. Creates systemd service (auto-start, auto-restart)
#   5. Configures nginx as SSL reverse proxy
#   6. Gets Let's Encrypt SSL certificate
#   7. Opens firewall ports
#   8. Starts everything

set -e

DOMAIN="krypton-lang.org"
EMAIL="brian@krypton-lang.org"
SITE_PORT="8080"
INSTALL_DIR="/opt/krypton"
SITE_DIR="/opt/krypton-site"

echo "============================================"
echo " krypton-lang.org server setup"
echo " Domain: $DOMAIN"
echo "============================================"
echo ""

# ── 1. Install dependencies ──────────────────────────────────────────

echo "[1/7] Installing dependencies..."
apt-get update -qq
apt-get install -y -qq gcc git nginx certbot python3-certbot-nginx curl ufw > /dev/null

# ── 2. Clone and build Krypton ────────────────────────────────────────

echo "[2/7] Building Krypton..."
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/t3m3d/krypton.git "$INSTALL_DIR"
else
    cd "$INSTALL_DIR" && git pull
fi

cd "$INSTALL_DIR"
./build.sh

# Make kcc available system-wide
ln -sf "$INSTALL_DIR/kcc" /usr/local/bin/kcc
# Copy stdlib to install root
mkdir -p /krypton/stdlib /krypton/headers
cp -r "$INSTALL_DIR/stdlib/"* /krypton/stdlib/
cp -r "$INSTALL_DIR/headers/"* /krypton/headers/

echo "  kcc ready: $(kcc --version 2>&1)"

# ── 3. Build site.htk ────────────────────────────────────────────────

echo "[3/7] Building site..."
mkdir -p "$SITE_DIR"

# Copy site source
cp "$INSTALL_DIR/web/site/site.htk" "$SITE_DIR/site.htk"

# Compile: Krypton → C → native binary
cd "$SITE_DIR"
kcc site.htk > site_tmp.c
gcc site_tmp.c -o site -w
rm -f site_tmp.c
chmod +x site

echo "  site binary: $(ls -lh site | awk '{print $5}')"

# ── 4. Create systemd service ────────────────────────────────────────

echo "[4/7] Creating systemd service..."
cat > /etc/systemd/system/krypton-site.service << 'UNIT'
[Unit]
Description=krypton-lang.org — Krypton Web Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/krypton-site
ExecStart=/opt/krypton-site/site
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/krypton-site
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable krypton-site

# ── 5. Configure nginx ───────────────────────────────────────────────

echo "[5/7] Configuring nginx..."
cat > /etc/nginx/sites-available/krypton-lang << NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    # SSL certs (certbot will fill these in)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Security headers
    add_header X-Powered-By "Krypton 2.1.0" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;" always;

    # Reverse proxy to Krypton server
    location / {
        proxy_pass http://127.0.0.1:$SITE_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/krypton-lang /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t

# ── 6. SSL certificate ───────────────────────────────────────────────

echo "[6/7] Getting SSL certificate..."

# Start nginx temporarily for HTTP challenge
systemctl start nginx

# First start the site so it's ready
systemctl start krypton-site
sleep 2

# Get cert (skip if already exists)
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
else
    echo "  SSL cert already exists, skipping"
fi

# ── 7. Firewall ──────────────────────────────────────────────────────

echo "[7/7] Configuring firewall..."
ufw allow 22/tcp    > /dev/null  # SSH
ufw allow 80/tcp    > /dev/null  # HTTP (redirect)
ufw allow 443/tcp   > /dev/null  # HTTPS
ufw --force enable  > /dev/null

# ── Done ─────────────────────────────────────────────────────────────

systemctl restart nginx
systemctl restart krypton-site

echo ""
echo "============================================"
echo " DONE"
echo "============================================"
echo ""
echo " Site:    https://$DOMAIN"
echo " Server:  Krypton (site.htk on :$SITE_PORT)"
echo " Proxy:   nginx (SSL termination)"
echo " Service: systemctl status krypton-site"
echo " Logs:    journalctl -u krypton-site -f"
echo ""
echo " To update the site:"
echo "   1. Edit site.htk"
echo "   2. Run: bash /opt/krypton-site/rebuild.sh"
echo ""
echo " SSL auto-renews via certbot timer."
echo "============================================"
