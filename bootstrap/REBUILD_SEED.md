# Rebuilding `bootstrap/elf_host_linux_x86_64`

The seed is the gcc-built ELF binary that compiles every Linux native build.
Today's seed predates several `compile.k` and `elf.k` fixes. To pick up those
fixes the seed must be rebuilt.

## Easy path: Linux box with gcc

```bash
./kcc-x64 compiler/linux_x86/elf.k > /tmp/elf_host.c
gcc /tmp/elf_host.c -o bootstrap/elf_host_linux_x86_64
chmod +x bootstrap/elf_host_linux_x86_64
```

Verify: `./build.sh test` should now show 38/38 instead of 26/38.

## Hard path: gcc-free, via the existing seed (PARTIAL — not working yet)

There's a `bootstrap/sanitize_ir.py` helper that pre-processes IR to dodge two
known seed bugs (escape decode + line-separator collision):

```bash
# 1. Generate IR (use Windows kcc-x64-new.exe — Linux kcc-x64-native segfaults
#    on files this size due to a separate memory leak)
kcc-x64-new.exe --ir compiler/linux_x86/elf.k > raw.kir

# 2. Sanitize (strip CR + rewrite escape-containing PUSH lines)
tr -d '\r' < raw.kir | python3 bootstrap/sanitize_ir.py > safe.kir

# 3. Build via seed
bootstrap/elf_host_linux_x86_64 safe.kir bootstrap/elf_host_linux_x86_64.new
```

**Status (2026-05-02):** sanitizer correctly handles the escape/separator bug
(verified on minimal cases). But there's a *third* unresolved seed bug: when
elf.k IR includes more than ~67 functions, the seed produces a binary whose
strData section is missing entries — string indices from late `PUSH "..."`
lines collide with earlier ones, so e.g. `print("hi")` outputs `"0"` (the
literal at index 4 in the truncated table). Bisect log:

| funcs | output of `print("hi")` |
|-------|------------------------|
| 50    | `hi`  ✓ |
| 66    | `hi`  ✓ |
| 67    | `0`   ✗ (regression here — adding `krIsdigitSize` is the trigger) |
| 100+  | `0`   ✗ |

Best guess: the seed's emission has an offset/index calculation that breaks
when the binary crosses ~170KB (n=66 = 170KB works, n=67 = 186KB broken).
Could be a runtime helper that the seed lazily includes once a certain
function is referenced, and that helper has its own bug. Needs deeper
disassembly to pin down — out of scope for tonight.

## Why the chicken-and-egg

- `compile.k` (today) emits IR with stack-balanced AND/OR + 2-char `\n`
  escapes (no double-encoding).
- The seed `elf_host` was built from older `compile.k`/`elf.k`. Its baked-in
  `parseQuoted` decodes `\n` to a real newline, then stuffs the value into a
  `\n`-separated `strTab`, truncating any string with a newline.
- Sanitizer rewrites `PUSH "...\n..."` → `PUSH "..."; PUSH "10"; BUILTIN
  fromCharCode 1; CAT; PUSH "..."; CAT` so no IR string contains an escape
  the seed mishandles. This works on small inputs but the seed has a third
  unrelated bug on full elf.k.

To fully break the cycle without gcc, we'd need to either patch the seed
binary directly, or write a strict subset of `elf.k` (`mini_elf.k`) that
self-hosts cleanly through this seed and can then build the full `elf.k`.
