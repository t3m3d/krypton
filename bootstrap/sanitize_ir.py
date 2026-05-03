#!/usr/bin/env python3
"""
sanitize_ir.py — pre-process Krypton IR so the OLD seed elf_host can compile
elf.k correctly.

Two bugs in bootstrap/elf_host_linux_x86_64 that this script works around:

1. parseQuoted decodes \\n / \\t / \\r escape sequences to their actual control
   bytes (0x0A / 0x09 / 0x0D), then returns "value\\nposition" — caller does
   getLine(parsed, 0) which splits on actual newline. Result: any string with
   \\n in it gets truncated at the first newline. internStr's strTab also uses
   \\n as line separator, compounding the loss. Strings with \\t suffer the
   same way against tabAppend's \\t separators.

2. Older compile.k emits stack-unbalanced AND/OR. New compile.k fixes that,
   but generating IR with the new compile.k means strings have 2-char escapes
   (no double-encoding), which feeds straight into bug #1.

Workaround: for every PUSH "...with \\n/\\t/\\r..." line, rewrite into a
PUSH+CAT+fromCharCode chain so no string literal in the IR contains an escape
that the seed's parseQuoted will mis-decode.

  Original:           Sanitized (functionally equivalent at runtime):
    PUSH "foo\\nbar"      PUSH "foo"
                          PUSH "10"
                          BUILTIN fromCharCode 1
                          CAT
                          PUSH "bar"
                          CAT

Other escapes (\\\\, \\", \\0) are storage-safe (no separator clash) and pass
through unchanged.

Usage:
    kcc-x64-native --ir compiler/linux_x86/elf.k > /tmp/raw.kir
    python3 bootstrap/sanitize_ir.py /tmp/raw.kir > /tmp/safe.kir
    bootstrap/elf_host_linux_x86_64 /tmp/safe.kir bootstrap/elf_host_linux_x86_64.new
"""

import sys, re

ESCAPE_TO_CHARCODE = {"n": "10", "t": "9", "r": "13"}
PUSH_RE = re.compile(r'^(\s*)PUSH "(.*)"\s*$')


def split_string_literal(content):
    """Split a string literal into segments alternating between literal text
    and bare control-char tokens (one of 'n', 't', 'r').

    Returns a list like ['foo', 'n', 'bar'] for "foo\\nbar". Other escapes
    (\\\\, \\", \\0, \\<other>) stay attached to the surrounding literal so
    they round-trip through the seed's parseQuoted (which handles them as
    1-char outputs that don't clash with line separators)."""
    parts = []
    cur = []
    i = 0
    while i < len(content):
        ch = content[i]
        if ch == "\\" and i + 1 < len(content):
            nxt = content[i + 1]
            if nxt in ESCAPE_TO_CHARCODE:
                parts.append("".join(cur))
                parts.append(nxt)
                cur = []
                i += 2
                continue
            # other escapes: keep as 2-char in literal
            cur.append(ch)
            cur.append(nxt)
            i += 2
            continue
        cur.append(ch)
        i += 1
    parts.append("".join(cur))
    return parts


def rewrite_push(indent, content):
    """Convert PUSH "...with-control-chars..." into PUSH+CAT chain."""
    parts = split_string_literal(content)
    # parts alternates literal,ctrl,literal,ctrl,... (always starts with literal,
    # always ends with literal — even if empty).
    out = []
    first = True
    for part in parts:
        if part in ESCAPE_TO_CHARCODE:
            code = ESCAPE_TO_CHARCODE[part]
            out.append(f'{indent}PUSH "{code}"')
            out.append(f'{indent}BUILTIN fromCharCode 1')
        else:
            out.append(f'{indent}PUSH "{part}"')
        if first:
            first = False
        else:
            out.append(f'{indent}CAT')
    return "\n".join(out)


def needs_sanitize(content):
    i = 0
    while i < len(content):
        if content[i] == "\\" and i + 1 < len(content):
            if content[i + 1] in ESCAPE_TO_CHARCODE:
                return True
            i += 2
            continue
        i += 1
    return False


def main():
    src = sys.stdin if len(sys.argv) < 2 or sys.argv[1] == "-" else open(sys.argv[1])
    out_lines = []
    for line in src:
        line = line.rstrip("\n").rstrip("\r")
        m = PUSH_RE.match(line)
        if m and needs_sanitize(m.group(2)):
            out_lines.append(rewrite_push(m.group(1), m.group(2)))
        else:
            out_lines.append(line)
    sys.stdout.write("\n".join(out_lines) + "\n")


if __name__ == "__main__":
    main()
