#!/usr/bin/env python3
"""Opaque-blob sync server for Krypton Vault.

This is the deployable VPS daemon. It deliberately stores only the encrypted
vault blob supplied by the client; it never receives the master password or
plaintext vault items.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
from hmac import compare_digest
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


SAFE_USER = re.compile(r"[^A-Za-z0-9_.-]+")
MAX_BLOB_BYTES = int(os.environ.get("KRYPTON_VAULT_MAX_BLOB_BYTES", str(10 * 1024 * 1024)))


def data_path() -> str:
    root = os.environ.get(
        "KRYPTON_VAULT_DATA",
        os.path.expanduser("~/.config/krypton-vault/server"),
    )
    os.makedirs(root, exist_ok=True)
    return os.path.join(root, "vault_sync.sqlite3")


def token() -> str:
    return os.environ.get("KRYPTON_VAULT_TOKEN", "")


def clean_user(value: str) -> str:
    cleaned = SAFE_USER.sub("", value.strip())
    return cleaned or "default"


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(data_path())
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS vaults (
            user TEXT PRIMARY KEY,
            rev INTEGER NOT NULL,
            blob TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    return conn


class Handler(BaseHTTPRequestHandler):
    server_version = "KryptonVaultSync/0.1"

    def log_message(self, fmt: str, *args: object) -> None:
        if os.environ.get("KRYPTON_VAULT_DEBUG") == "1":
            super().log_message(fmt, *args)

    def send_json(self, status: HTTPStatus, payload: dict[str, object]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, status: HTTPStatus, body_text: str) -> None:
        body = body_text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def read_form(self) -> dict[str, str]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length > MAX_BLOB_BYTES:
            return {"__too_large__": "1"}
        body = self.rfile.read(length).decode("utf-8")
        parsed = parse_qs(body, keep_blank_values=True)
        return {key: values[-1] if values else "" for key, values in parsed.items()}

    def authorized(self, values: dict[str, str]) -> bool:
        expected = token()
        return bool(expected) and compare_digest(values.get("token", ""), expected)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        query = {key: values[-1] if values else "" for key, values in parse_qs(parsed.query).items()}

        if parsed.path == "/health":
            self.send_json(HTTPStatus.OK, {"ok": True, "service": "krypton-vault-sync"})
            return

        if parsed.path not in ("/v1/vault", "/v1/vault/blob"):
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return

        if not self.authorized(query):
            self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            return

        user = clean_user(query.get("user", ""))
        with db() as conn:
            row = conn.execute("SELECT rev, blob FROM vaults WHERE user = ?", (user,)).fetchone()
        if row is None:
            if parsed.path == "/v1/vault/blob":
                self.send_text(HTTPStatus.NOT_FOUND, "")
                return
            self.send_json(HTTPStatus.OK, {"user": user, "rev": 0, "blob": ""})
            return
        if parsed.path == "/v1/vault/blob":
            self.send_text(HTTPStatus.OK, row[1])
            return
        self.send_json(HTTPStatus.OK, {"user": user, "rev": row[0], "blob": row[1]})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/v1/vault":
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
            return

        form = self.read_form()
        if form.get("__too_large__") == "1":
            self.send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "too_large"})
            return
        if not self.authorized(form):
            self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
            return

        user = clean_user(form.get("user", ""))
        blob = form.get("blob", "")
        if not user:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "missing_user"})
            return
        if not blob.startswith("KV2\n"):
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "invalid_blob"})
            return

        with db() as conn:
            row = conn.execute("SELECT rev FROM vaults WHERE user = ?", (user,)).fetchone()
            rev = int(row[0]) + 1 if row else 1
            conn.execute(
                """
                INSERT INTO vaults (user, rev, blob)
                VALUES (?, ?, ?)
                ON CONFLICT(user) DO UPDATE SET
                    rev = excluded.rev,
                    blob = excluded.blob,
                    updated_at = CURRENT_TIMESTAMP
                """,
                (user, rev, blob),
            )
        self.send_json(HTTPStatus.OK, {"ok": True, "user": user, "rev": rev})


def main() -> None:
    if not token():
        raise SystemExit("KRYPTON_VAULT_TOKEN is required")
    port = int(os.environ.get("PORT", "8080"))
    host = os.environ.get("HOST", "127.0.0.1")
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"krypton-vault-sync listening on http://{host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
