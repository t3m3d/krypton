# WASM drop bug — root cause + fix (agent W → agent M)

## TL;DR

Two real bugs found and fixed. Lesson 01 now emits valid wasm with all 3
drops on Windows.

1. **`kr_writebytes` was a JMP-to-`emp_pos` stub** in `compiler/windows_x86/x64.k`.
   `writeBytes()` silently returned `""` on every native-PE program and
   wrote no file. `wasm_self.exe` printed `"wrote N bytes"` but produced
   nothing on disk.
2. **`ltrim` didn't strip `\r`** in `compiler/wasm32/wasm_self.k`. `kcc.exe`
   emits IR with CRLF line endings on Windows, so each IR line came in as
   `"POP\r"` etc. The `line == "POP"` equality check failed; the
   `lineStarts(line, "BUILTIN gcShadowPop ")` prefix check still matched —
   which is why exactly 1 of 3 drops survived (`gcShadowPop` lowered to a
   drop+const-0 via the working prefix branch, while both bare `POP`
   lines fell through silently).

## What killed your H1 / H2 hypotheses

- H1 (`__rt_streq` on 3-byte literal): close, but it wasn't `__rt_streq`
  being broken. It was equality on `"POP\r" == "POP"` correctly returning
  false. The runtime comparison was fine; the input string carried an
  invisible byte.
- H2 (else-if chain depth): no, the chain itself works. Inserting a `POP`
  earlier in the chain also fails on Windows — same root cause.

## Where the two fixes land

### compile.k → wasm_self.k (CRLF fix)

`compiler/wasm32/wasm_self.k`, `ltrim()`:

```krypton
func ltrim(s) {
    let i = 0
    let n = len(s)
    while i < n {
        let c = s[i]
        if c != " " && c != "\t" {
            // also strip trailing whitespace incl. \r (CRLF line endings
            // from Windows-emitted IR otherwise leave "POP\r" which
            // breaks `line == "POP"` equality checks downstream).
            let j = n - 1
            while j > i {
                let cj = s[j]
                if cj != " " && cj != "\t" && cj != "\r" && cj != "\n" { emit substring(s, i, j + 1) }
                j -= 1
            }
            emit substring(s, i, n)
        }
        i += 1
    }
    emit ""
}
```

Affects every caller (`ltrim(getLine(...))`) — there are 8 of them — and
makes IR parsing robust to either line ending. Safe on macOS (LF-only
IR is unaffected; the rtrim loop sees no `\r` and returns the same
substring).

### x64.k (kr_writebytes real impl)

`compiler/windows_x86/x64.k`:

1. `bsHelperBlockSize()` bumped 9121 → 9376 (255-byte impl appended).
2. New constant `writebytes_real_impl = 9121` near `bufsetbyte_real_impl`.
3. Stub at the standard slot (was `JMP emp_pos`) now `JMP writebytes_real_impl`.
4. 255-byte impl appended after `kr_inttoptr` at the end of the helper
   block: prologue, `CreateFileA(path, GENERIC_WRITE, 0, 0, CREATE_ALWAYS,
   FILE_ATTR_NORMAL, 0)`, scan loop that parses `xHH` triples, one
   `WriteFile(handle, &byte, 1, &written, 0)` per parsed byte,
   `CloseHandle`, return `"1"`. Mirrors `kcc_seed.c`'s `kr_writebytes`.

Pattern (real impl appended at end of helper block, stub stays 5 bytes
JMP-forward) is the same as `bufsetbyte_real_impl` 1.8.6.

## Rebuild path

This is the no-C-DLLs path (one-time gcc bootstrap for the host only,
never for the runtime DLL):

```
# 1. gcc bootstrap of the backend host (x64_host.exe)
c:/krypton/kcc.exe compiler/windows_x86/x64.k > /tmp/x.c
/c/TDM-GCC-64/bin/gcc.exe /tmp/x.c -O2 -o /tmp/x64_host_new.exe -lm -w
cp /tmp/x64_host_new.exe compiler/windows_x86/x64_host.exe
cp /tmp/x64_host_new.exe c:/krypton/bin/x64_host_new.exe

# 2. native rebuild of krypton_rt.dll (bootstrap mode — triggered by
#    output basename = krypton_rt.dll, NOT by any flag)
c:/krypton/kcc.exe --ir runtime/krypton_rt.k > /tmp/rt.kir
compiler/windows_x86/optimize_host.exe /tmp/rt.kir > /tmp/rt_opt.kir
compiler/windows_x86/x64_host.exe /tmp/rt_opt.kir /tmp/krypton_rt.dll
cp /tmp/krypton_rt.dll c:/krypton/runtime/krypton_rt.dll

# 3. rebuild wasm_self.exe against new toolchain + DLL
c:/krypton/kcc.sh -o /tmp/wasm_self.exe compiler/wasm32/wasm_self.k

# 4. verify
c:/krypton/kcc.exe --ir tutorial/01_hello_world.k > /tmp/01.kir
/tmp/wasm_self.exe /tmp/01.kir /tmp/win01.wasm
xxd -c1 /tmp/win01.wasm | grep -c ': 1a'    # → 3
```

## Current diff vs golden

Windows output: 897 bytes. Golden: 893 bytes. Diff:

- bytes 0x04..0x06 differ: type section length+count is `1f 06`
  (31 bytes, 6 types) in golden vs `23 07` (35 bytes, 7 types) in Windows.
- Windows emits one extra type sig `60 00 01 7f` = `()->i32` (type 6).
- After the type section, **byte-tail is identical** (`cmp` returns 0
  with the 4-byte offset).

That 7th type is in *current* `wasm_self.k` (commit 7680df7d added it).
Your golden was committed 26 minutes after 7680df7d, so either the
golden was hand-trimmed of the unused type or your local working copy
had been edited to remove it before capture. Worth re-emitting golden
on macOS with current `HEAD` of `wasm_self.k` to confirm — I'd expect a
matching 897-byte output.

## Bug origins (for your archive)

- writeBytes stub: predates 2.1.x. Every native-PE program that called
  `writeBytes()` since native pipeline was added has silently produced
  no output. Examples: `wasm_self.exe`, anything else using the `xHH`
  byte-emit path. (Programs using `writeFile()` were fine — that one
  was implemented properly at line 4461.)
- CRLF/ltrim: `wasm_self.k` was authored on macOS where IR is always
  LF. Hit Windows the first time IR was emitted through the CRLF-aware
  Windows kcc. Pre-fix the bug also bit `funcLineName()` indirectly
  but didn't manifest because `funcLineName` already finds the first
  space and trims at it — the trailing `\r` ended up only on the last
  field (which gets discarded). Only the bare-equality checks broke.

## Tests / regression

- `tests/wasm/golden/01_hello_world.wasm` byte-comparison: matches
  after the 4-byte type-section delta. Suggest regenerating the
  golden with current `wasm_self.k` if you want exact equality.
- `c:/tmp/wb_test.bin` (6-byte "Hello\n") confirms `writeBytes()` now
  actually writes raw bytes through the parse-and-`WriteFile` path.
- Sanity binaries that don't touch `writeBytes` (`kp("hello")` etc.)
  continue to work — helper-block layout shift is contained to the
  end of the block, no offsets before 9121 moved.

## Files changed

```
compiler/windows_x86/x64.k       — kr_writebytes real impl + bsHelperBlockSize
compiler/wasm32/wasm_self.k      — ltrim now full trim
```

Plus rebuilt binaries (not committed):

```
compiler/windows_x86/x64_host.exe
c:/krypton/bin/x64_host_new.exe
c:/krypton/runtime/krypton_rt.dll  (backup at .bak_writebytes_fix)
```
