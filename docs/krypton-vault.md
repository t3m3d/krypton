# Krypton Vault

Krypton Vault is the password manager product track for this repo.

The platform order is:

1. macOS
2. Windows
3. Linux
4. BSD, only if there is real demand

The first shippable product should be a small native desktop app with optional
VPS sync. The desktop client owns encryption and decryption. The VPS should
only store opaque encrypted vault blobs, account records, device metadata, and
sync revisions.

## First macOS Build

The first macOS prototype lives at:

```text
examples/objk/krypton_vault.ks
```

Build it as an app bundle with:

```bash
kcc -r scripts/build-objk-app.ks examples/objk/krypton_vault.ks krypton-vault
```

This creates:

```text
dist/krypton-vault.app
```

The current prototype has encrypted local persistence through:

```text
stdlib/vault_crypto_macos.k
```

That module is a native macOS bridge over Security.framework and CommonCrypto.
It uses OS random bytes, AES-256-CBC with PKCS7 padding, and HMAC-SHA256, then
writes:

```text
~/.config/krypton-vault/vault.kv
```

The UI can unlock, add items, delete the first search match, filter the visible
vault list, copy the first matching saved password, copy the edited password,
save an encrypted local vault, upload the sealed vault blob to the VPS sync
service, and restore a sealed vault from the VPS on a fresh client.

This is good enough for the product slice to move forward, but it is not the
final hardened crypto implementation. Before a public release, replace the
prototype HMAC-based master-key derivation with a reviewed memory-hard KDF and
get the vault format reviewed.

## Security Gates

Before a hardened public release, the macOS build needs:

- Argon2id or another reviewed memory-hard KDF for the master password.
- Authenticated encryption for vault data, preferably XChaCha20-Poly1305 or
  AES-GCM through a reviewed platform/library binding.
- Secure random bytes from the OS.
- A vault file format with version, KDF parameters, salt, nonce, ciphertext,
  and auth tag.
- Local auto-lock behavior.
- No plaintext vault writes, logs, crash dumps, or sync payloads.

The Windows second build can reuse the OKUI product shell and wire the crypto
through CNG (`bcrypt.dll`). Linux should come after the sync and vault format
are stable.

## VPS Role

The VPS can stay deliberately boring:

- HTTPS API
- user account records
- device/session records
- encrypted vault blob revisions
- conflict metadata
- encrypted backup retention

The server must not receive the master password, derived vault key, plaintext
items, or decrypted metadata.

The deployable sync server lives at:

```text
tools/vault_sync_server.py
```

It uses only the Python standard library and stores opaque client-encrypted
vault blobs in SQLite. Uploads are capped by `KRYPTON_VAULT_MAX_BLOB_BYTES`,
which defaults to 10 MB.

Run it on the VPS behind nginx/Caddy/Apache TLS termination:

```bash
export HOST=127.0.0.1
export PORT=8080
export KRYPTON_VAULT_TOKEN='change-this-long-random-token'
export KRYPTON_VAULT_DATA="$HOME/.config/krypton-vault/server"
python3 tools/vault_sync_server.py
```

Deployable VPS files live in:

```text
deploy/krypton-vault/
```

That folder includes a systemd unit, env-file example, Caddy reverse-proxy
stanza, and operator README.

The pure-Krypton server experiment lives at:

```text
examples/ks/vault_sync_server.ks
```

Keep that as a language/runtime target for later. The tested VPS path for now is
the Python daemon.

Health check:

```bash
curl https://vault.example.com/health
```

Vault fetch:

```bash
curl 'https://vault.example.com/v1/vault?user=alice&token=TOKEN'
```

Raw sealed-vault fetch for desktop restore:

```bash
curl -G https://vault.example.com/v1/vault/blob \
  --data-urlencode 'user=alice' \
  --data-urlencode 'token=TOKEN'
```

Vault upload:

```bash
curl -X POST https://vault.example.com/v1/vault \
  -d 'user=alice' \
  -d 'token=TOKEN' \
  -d 'rev=1' \
  --data-urlencode 'blob=OPAQUE_CLIENT_ENCRYPTED_BLOB'
```

This server is not the security boundary. It is a dumb sync target. The desktop
client must encrypt before upload and authenticate/decrypt after download.

## Minimal Sync API

```text
GET  /v1/vault
GET  /v1/vault/blob
POST /v1/vault
GET  /health
```

For the first VPS, SQLite is enough. The hard part is the client crypto and the
update/conflict rules, not storage size.

## Local Vault Format

The current sealed local file is text-shaped for easier debugging:

```text
KV2
kdf=hmac-sha256-2block
iterations=1
cipher=aes-256-cbc-hmac-sha256
salt=...
iv=...
tag=...
ciphertext=...
```

`KV2` is a working prototype format, not the final public vault format. The
next hardening pass should move the KDF to Argon2id, scrypt, or a reviewed
platform-equivalent derivation before real customer data is trusted to it.

The decrypted payload is currently structured JSON. Old `KVPLAIN1`
tab-delimited local payloads can still be rendered by the app, but new saves
use:

```text
KVJSON1
{"version":1,"items":[{"title":"...","username":"...","url":"...","password":"..."}]}
```

This JSON shape is still intentionally small. Sharing, attachments, item IDs,
timestamps, and conflict resolution should extend this payload before browser
extensions or mobile clients.

## Verification

Full local verification:

```bash
tools/vault_verify.sh
```

That builds the macOS app, checks the structured vault format, checks
seal/open crypto, syntax-checks the VPS daemon, starts a local sync server,
exercises health/upload/fetch/raw restore, and shuts the server down.

Individual local checks:

```bash
kcc -r examples/ks/vault_format_smoke.ks
tools/vault_verify.sh
kcc -r scripts/build-objk-app.ks examples/objk/krypton_vault.ks krypton-vault
python3 -m py_compile tools/vault_sync_server.py
```

For the sync server:

```bash
export BASE_URL=http://127.0.0.1:8080
export KRYPTON_VAULT_TOKEN='change-this-long-random-token'
tools/vault_sync_smoke.sh
```

## Next Implementation Step

The next real work item is hardening the native/shared crypto implementation
while preserving a shared vault format:

```text
version
kdf name and parameters
salt
nonce
ciphertext
auth tag
revision
```

Once macOS can seal/open that format locally, Windows can implement the same
format through CNG and reuse the app flow.
