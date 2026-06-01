#!/usr/bin/env python3
# lsp/test_kls.py - smoke test for kls.exe (Krypton Language Server)
#
# Pipes a sequence of framed LSP requests into kls.exe and prints the
# framed responses. Run from repo root:
#   python lsp/test_kls.py

import subprocess
import json
import sys
import os

# Code with a tokenizer error (unterminated string) AND structural
# error (missing `}` for func body, mismatched paren).
BAD_CODE = '''func main() {
    let x = "unterminated
    if (x > 5  {
        kp(x)
    }
'''

GOOD_CODE = '''module sample

func add(a, b) {
    emit a + b
}

func greet(name) {
    kp("hello " + name)
}

func main() {
    let x = add(2, 3)
    greet("world")
}
'''

# Trigger duplicate-function warning
DUP_CODE = '''func foo() { emit 1 }
func bar() { emit 2 }
func foo() { emit 3 }
'''


def frame(obj):
    body = json.dumps(obj).encode("utf-8")
    return f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body


def read_frame(stream):
    headers = {}
    while True:
        line = stream.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n", b""):
            break
        if b":" in line:
            k, _, v = line.partition(b":")
            headers[k.strip().lower()] = v.strip()
    n = int(headers.get(b"content-length", b"0"))
    # stream.read(n) on a pipe may return fewer than n bytes;
    # loop until we have the whole body.
    chunks = []
    remaining = n
    while remaining > 0:
        chunk = stream.read(remaining)
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    kls_path = os.path.join(repo_root, "kls.exe")
    if not os.path.exists(kls_path):
        print(f"kls.exe not found at {kls_path}", file=sys.stderr)
        sys.exit(1)

    proc = subprocess.Popen(
        [kls_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )

    bad_uri = "file:///tmp/bad.k"
    good_uri = "file:///tmp/good.k"
    dup_uri = "file:///tmp/dup.k"

    requests = [
        # --- handshake ---
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"processId": os.getpid(), "rootUri": None, "capabilities": {}}},
        {"jsonrpc": "2.0", "method": "initialized", "params": {}},

        # --- diagnostics: bad code ---
        {"jsonrpc": "2.0", "method": "textDocument/didOpen",
         "params": {"textDocument": {"uri": bad_uri, "languageId": "krypton",
                                     "version": 1, "text": BAD_CODE}}},

        # --- diagnostics: clean it up via didChange ---
        {"jsonrpc": "2.0", "method": "textDocument/didChange",
         "params": {"textDocument": {"uri": bad_uri, "version": 2},
                    "contentChanges": [{"text": GOOD_CODE}]}},

        # --- documentSymbol on the now-good doc ---
        {"jsonrpc": "2.0", "id": 10, "method": "textDocument/documentSymbol",
         "params": {"textDocument": {"uri": bad_uri}}},

        # --- completion on the same doc ---
        {"jsonrpc": "2.0", "id": 11, "method": "textDocument/completion",
         "params": {"textDocument": {"uri": bad_uri},
                    "position": {"line": 0, "character": 0}}},

        # --- duplicate-function warning ---
        {"jsonrpc": "2.0", "method": "textDocument/didOpen",
         "params": {"textDocument": {"uri": dup_uri, "languageId": "krypton",
                                     "version": 1, "text": DUP_CODE}}},

        {"jsonrpc": "2.0", "id": 99, "method": "shutdown"},
        {"jsonrpc": "2.0", "method": "exit"},
    ]

    for r in requests:
        proc.stdin.write(frame(r))
        proc.stdin.flush()
    proc.stdin.close()

    print("=" * 60)
    print("RESPONSES")
    print("=" * 60)
    while True:
        body = read_frame(proc.stdout)
        if body is None:
            break
        try:
            parsed = json.loads(body)
            label = parsed.get("method") or f"id={parsed.get('id')}"
            # Compact display for big results so we don't drown in
            # 150-entry completion lists.
            if isinstance(parsed.get("result"), list):
                items = parsed["result"]
                print(f"\n--- {label}: {len(items)} items ---")
                for it in items[:5]:
                    print(json.dumps(it, indent=2))
                if len(items) > 5:
                    print(f"... ({len(items) - 5} more)")
            elif isinstance(parsed.get("result"), dict) and "items" in parsed["result"]:
                items = parsed["result"]["items"]
                print(f"\n--- {label}: {len(items)} completion items ---")
                kinds = {}
                for it in items:
                    detail = it.get("detail", "?")
                    kinds[detail] = kinds.get(detail, 0) + 1
                for k, v in kinds.items():
                    print(f"  {k}: {v}")
                user_funcs = [it["label"] for it in items if it.get("detail") == "user function"]
                if user_funcs:
                    print(f"  user functions: {user_funcs}")
            else:
                print(f"\n--- {label} ---")
                print(json.dumps(parsed, indent=2)[:2000])
        except Exception as e:
            print(f"<<unparseable>> {body!r} ({e})")

    proc.wait(timeout=5)

    print("\n" + "=" * 60)
    print("STDERR")
    print("=" * 60)
    err = proc.stderr.read().decode("utf-8", errors="replace")
    print(err)
    print(f"exit code: {proc.returncode}")


if __name__ == "__main__":
    main()
