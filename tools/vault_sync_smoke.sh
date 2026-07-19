#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
TOKEN="${KRYPTON_VAULT_TOKEN:?KRYPTON_VAULT_TOKEN is required}"
USER_NAME="${KRYPTON_VAULT_USER:-smoke}"

curl -fsS --max-time 5 "$BASE_URL/health" >/dev/null
curl -fsS --max-time 5 -X POST "$BASE_URL/v1/vault" \
  --data-urlencode "user=$USER_NAME" \
  --data-urlencode "token=$TOKEN" \
  --data-urlencode $'blob=KV2\nkdf=smoke\nciphertext=dummy\n' >/dev/null

fetched="$(curl -fsS --max-time 5 "$BASE_URL/v1/vault?user=$USER_NAME&token=$TOKEN")"
case "$fetched" in
  *'"blob":"KV2\nkdf=smoke\nciphertext=dummy\n"'*) ;;
  *) echo "vault sync smoke failed" >&2; exit 1 ;;
esac

raw="$(curl -fsS --max-time 5 -G "$BASE_URL/v1/vault/blob" \
  --data-urlencode "user=$USER_NAME" \
  --data-urlencode "token=$TOKEN")"
case "$raw" in
  $'KV2\nkdf=smoke\nciphertext=dummy') echo "vault sync smoke ok" ;;
  *) echo "vault raw restore smoke failed" >&2; exit 1 ;;
esac
