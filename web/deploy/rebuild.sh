#!/usr/bin/env bash
# rebuild.sh — rebuild and restart the Krypton site after edits
# Run: bash /opt/krypton-site/rebuild.sh

set -e
cd /opt/krypton-site

echo "kweb: rebuilding site..."
kcc site.htk > site_tmp.c
gcc site_tmp.c -o site_new -w
rm -f site_tmp.c

# Hot swap: replace binary and restart service
mv site_new site
chmod +x site

echo "kweb: restarting service..."
systemctl restart krypton-site
sleep 1
systemctl is-active krypton-site

echo "kweb: done — site is live"
