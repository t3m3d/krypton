# Krypton Vault VPS Deploy

This deploys the blind sync service. The VPS stores only encrypted vault blobs.
It never receives the master password, derived key, or plaintext vault items.

## Files

```text
tools/vault_sync_server.py                  service binary/script
deploy/krypton-vault/krypton-vault-sync.service
deploy/krypton-vault/krypton-vault-sync.env.example
deploy/krypton-vault/Caddyfile
tools/vault_sync_smoke.sh                   health/upload/fetch smoke test
```

## Install

Run as root on the VPS:

```bash
useradd --system --home /var/lib/krypton-vault --shell /usr/sbin/nologin krypton-vault
mkdir -p /opt/krypton /etc/krypton-vault /var/lib/krypton-vault
cp -R /path/to/krypton/* /opt/krypton/
cp /opt/krypton/deploy/krypton-vault/krypton-vault-sync.service /etc/systemd/system/
cp /opt/krypton/deploy/krypton-vault/krypton-vault-sync.env.example /etc/krypton-vault/sync.env
chown -R krypton-vault:krypton-vault /var/lib/krypton-vault
chmod 600 /etc/krypton-vault/sync.env
```

Edit `/etc/krypton-vault/sync.env` and set a long random
`KRYPTON_VAULT_TOKEN`.

`KRYPTON_VAULT_MAX_BLOB_BYTES` defaults to 10 MB. That is plenty for the
current no-attachments vault format; increase it only when encrypted
attachments exist.

Then:

```bash
systemctl daemon-reload
systemctl enable --now krypton-vault-sync
systemctl status krypton-vault-sync
```

## Reverse Proxy

With Caddy, copy the sample `Caddyfile` stanza and replace
`vault.example.com` with the real hostname.

The service should stay bound to `127.0.0.1`; TLS terminates at the reverse
proxy.

## Smoke Test

From a trusted machine:

```bash
export BASE_URL=https://vault.example.com
export KRYPTON_VAULT_TOKEN='same-token-from-sync.env'
tools/vault_sync_smoke.sh
```

Expected:

```text
vault sync smoke ok
```
