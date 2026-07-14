#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-19097}"
TOKEN="${KRYPTON_VAULT_TOKEN:-test-token}"
DATA_DIR="${KRYPTON_VAULT_DATA:-/tmp/krypton-vault-verify}"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$ROOT/tools/__pycache__"
}
trap cleanup EXIT

cd "$ROOT"

FE="$ROOT/compiler/macos_arm64/kcc-arm64"
HOST_BIN="$ROOT/compiler/macos_arm64/macho_host"
BACKEND="$ROOT/compiler/macos_arm64/macho_arm64_self.k"
if [[ ! -x "$HOST_BIN" || "$BACKEND" -nt "$HOST_BIN" ]]; then
  env KRYPTON_ROOT="$ROOT" "$FE" "$BACKEND" > /tmp/krypton-vault-macho-host.kir
  "$HOST_BIN" --ir /tmp/krypton-vault-macho-host.kir /tmp/krypton-vault-macho-host
  cp /tmp/krypton-vault-macho-host "$HOST_BIN"
  chmod +x "$HOST_BIN"
fi

kcc -r examples/ks/vault_format_smoke.ks
env KRYPTON_ROOT="$ROOT" "$FE" examples/ks/vault_crypto_smoke.ks > /tmp/krypton-vault-crypto-smoke.kir
"$HOST_BIN" --ir /tmp/krypton-vault-crypto-smoke.kir /tmp/krypton-vault-crypto-smoke
chmod +x /tmp/krypton-vault-crypto-smoke
/tmp/krypton-vault-crypto-smoke
kcc -r scripts/build-objk-app.ks examples/objk/krypton_vault.ks krypton-vault
python3 -m py_compile tools/vault_sync_server.py

rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"
HOST=127.0.0.1 PORT="$PORT" KRYPTON_VAULT_TOKEN="$TOKEN" KRYPTON_VAULT_DATA="$DATA_DIR" \
  python3 tools/vault_sync_server.py >/tmp/krypton-vault-verify-server.log 2>&1 &
SERVER_PID="$!"

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done

if [[ "$ready" != "1" ]]; then
  cat /tmp/krypton-vault-verify-server.log >&2 || true
  echo "vault verify failed: sync server did not become ready" >&2
  exit 1
fi

BASE_URL="http://127.0.0.1:$PORT" KRYPTON_VAULT_TOKEN="$TOKEN" KRYPTON_VAULT_USER=verify \
  tools/vault_sync_smoke.sh

echo "vault verify ok"
