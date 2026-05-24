# Handoff — macOS arm64 follow-up after Windows IO helpers ship

**Date:** 2026-05-23
**Audience:** macOS arm64 session picking up after Windows shipped readLine/shellRun/exec inline-emitted builtins.
**Companion docs:** `docs/HANDOFF_M1.md` (M1 setup), `memory/project_windows_io_helpers.md` (full Windows session notes).

---

## What just shipped on Windows

Three IO builtins added to `compiler/windows_x86/x64.k`, inline-emitted at call sites (same pattern as macOS arm64 `BUILTIN_*` ops):

| Helper           | Bytes | Behavior                                                                                                                          |
|------------------|-------|-----------------------------------------------------------------------------------------------------------------------------------|
| `readLine(p)`    | 195   | Write prompt to stdout, ReadFile from stdin, strip `\r\n`, return.                                                                |
| `shellRun(cmd)`  | 314   | Spawn `cmd /C cmd` via CreateProcessA, WaitForSingleObject, CloseHandle×2. Returns `"0"` (hardcoded — not real exit code yet).    |
| `exec(cmd)`      | 613   | CreatePipe(SA inheritable) → CreateProcessA(STARTF_USESTDHANDLES + bInherit=TRUE) → ReadFile loop → TerminateProcess → Wait. Caps output at 65 536 bytes. |

97/97 tests pass. Architecture A (inline, no rt.dll helpers) chosen to mirror macOS — no `bsHelperBlockSize` cascade, no bootstrap IAT extension.

### Four bugs found and fixed (worth scanning macOS for parity)

1. **CreateProcessA stack alignment.** readLine works with `SUB RSP, 0x40` (misaligned by 8). CreateProcessA does NOT tolerate misalignment — crashes. shellRun/exec use `SUB RSP, 0xE8/0x150` so RSP stays 16-aligned at every CALL. **macOS check:** arm64 always requires 16-byte SP alignment, so this likely already handled — but verify `arm64_sub_sp(N)` value in `BUILTIN_EXEC`/`BUILTIN_SHELLRUN` is a multiple of 16.

2. **CreatePipe needs SECURITY_ATTRIBUTES bInheritHandle=TRUE.** Windows-specific (pipe() on macOS is fine without).

3. **MOV EAX vs MOV RAX zero-extend.** ReadFile writes `lpNumberOfBytesRead` as DWORD; loading via MOV RAX picks up 8 bytes of stack garbage. Fixed with 32-bit MOV. **macOS check:** SYS_read returns full 64-bit count in x0 — no DWORD/QWORD ambiguity, so this bug does not exist on macOS.

4. **exec deadlock when output > buffer cap.** This one **does apply to macOS** — see "Action items" below.

---

## Action items for macOS

### 1. exec buffer overflow when output exceeds 64 KB *(bug)*

`compiler/macos_arm64/macho_arm64_self.k:3640-3666` (`BUILTIN_EXEC` body) allocates 64 KB at instruction 35 (`x4 = 0x10000`) then runs a read loop (`READ_LOOP @ 59`):

```
add x1, x22, x23      ; buf+offset
mov w2, #0x1000        ; 4 KB chunk
svc 0x80               ; SYS_read
cbz x0, READ_DONE      ; break on EOF
add x23, x23, x0       ; total += bytes
b READ_LOOP            ; keep going
```

**No cap check.** If child writes > 64 KB, `add x1, x22, x23` produces a pointer past the 64 KB allocation and `SYS_read` writes through it → silent heap/arena corruption.

Two ways to fix, parallel to what Windows now does:

- **Easy / Windows-parity:** Cap reads. Before each `SYS_read`, compute `remaining = 0x10000 - x23`; if ≤ 0 break, otherwise clamp chunk to `min(0x1000, remaining)`. Then after the loop send the child a signal so it stops trying to write (Windows uses `TerminateProcess(hProcess, 1)` between read loop and `wait4` — on macOS do `SYS_kill(pid, SIGTERM=15)` or `SIGKILL=9` before `SYS_wait4`). Without that, `wait4` blocks because the child is stuck in `write()` on a full pipe.
- **Proper:** Grow the buffer (`mmap`/`mremap` or arena realloc) when offset approaches cap. macOS has no `HeapReAlloc` equivalent — would need a fresh allocation + memcpy.

Either approach matches the cap to the current behavior. The Windows fix in `compiler/windows_x86/x64.k` (see `emitExecInline`, ~lines 1140-1340) uses the easy path: cap at 65 536, then `TerminateProcess` before `WaitForSingleObject`. Output truncates cleanly, no deadlock.

Test that proved the deadlock on Windows (and would corrupt heap on macOS):
```
just run {
    let out = exec("ls /usr/bin")    // or any command with > 64 KB output
    kp("len=" + len(out))
}
```

### 2. shellRun exit code is hardcoded `"0"` *(feature parity)*

Both Windows and macOS hardcode the return value. Windows does WaitForSingleObject but never calls GetExitCodeProcess. macOS does `SYS_wait4` and gets the status in x0 — it's discarded. Either side could thread the real exit status through and itoa it into the return string.

Useful when callers want to write `if shellRun("git status") != "0" { ... }`. Low priority — but cheap on macOS since `wait4` already produces the value.

### 3. `mapHas` / `mapGet` / `mapSet` format conflict *(still deferred)*

macOS arm64 already inline-emits these (`BUILTIN_MAPGET` etc. at `macho_arm64_self.k:3689+`). They use the flat format `"k1,v1,k2,v2,..."`.

`stdlib/map.k` uses `"k=v\n..."`. Right now those native impls are unreachable from Krypton code because the name resolution doesn't route through them for stdlib maps — but if Windows ports them next session, it will silently break every caller of `stdlib/map.k` (including `stdlib/json.k`).

**Pick one format before either platform ships the native overrides.** Recommended: keep `stdlib/map.k`'s `k=v\n` format and reimplement the native helpers to match — it's the format that exists in the wild.

### 4. cmdline buffer leak *(minor)*

Both `shellRun` and `exec` HeapAlloc/malloc the `"cmd /C "` (Windows) or `"-c", argv` (macOS) command buffer and never free it. Per-call leak ~20-200 bytes. Add HeapFree (Windows) / SYS_munmap or arena-free (macOS) before return. Trivial — defer until someone runs into it.

---

## File reference

| Platform     | Backend file                                    | Helper region                            |
|--------------|-------------------------------------------------|------------------------------------------|
| Windows x64  | `compiler/windows_x86/x64.k`                    | `inlineBuiltinSize` + `emitReadLineInline` / `emitShellRunInline` / `emitExecInline` around lines 870-1340. |
| macOS arm64  | `compiler/macos_arm64/macho_arm64_self.k`       | `BUILTIN_READLINE` / `BUILTIN_SHELLRUN` / `BUILTIN_EXEC` / `BUILTIN_MAPGET`/`SET`/`HAS` around lines 3478-3920. Sizes in `instrSize` at line ~1763. |
| Linux x86_64 | `compiler/linux_x86/elf.k`                      | Not started. Different again — ELF + syscall (no IAT) but same logical algorithm as macOS arm64. |

---

## Rebuild paths

**Windows** (native self-compile broken — see `memory/project_self_compile_bug.md`):
```
kcc.exe compiler/windows_x86/x64.k > /tmp/x64new.c
gcc /tmp/x64new.c -O2 -o /tmp/x64new.exe -lm -w
cp /tmp/x64new.exe bin/x64_host_new.exe
cp /tmp/x64new.exe c:/krypton/bin/x64_host_new.exe
```

**macOS arm64** (self-compile works on macOS):
```
./compiler/macos_arm64/kcc-arm64 compiler/macos_arm64/macho_arm64_self.k
mv a.out compiler/macos_arm64/kcc-arm64.new
chmod +x compiler/macos_arm64/kcc-arm64.new
# swap in once tests pass
```

---

## Tests to mirror

The Windows side added these. Same names will work on macOS once exec is fixed:

- `tests/test_readline.k`
- `tests/test_shellrun.k`
- `tests/test_shellrun_exit.k`
- `tests/test_exec.k`
- `tests/test_exec_pre.k`, `tests/test_exec_concat.k`, `tests/test_exec_twice.k` — regressions for the MOV-RAX zero-extend bug (probably no-op on macOS but cheap to run)
- new test worth adding both sides: `tests/test_exec_long.k` — invoke a > 64 KB output command, assert it doesn't hang and returns truncated length.

---

## Quick sanity once macOS work begins

```bash
# parity smoke
./compiler/macos_arm64/kcc-arm64 tests/test_exec.k && ./a.out
# should print: captured = [captured\n]
```

If that works, the existing macOS impl is fine for short outputs. The buffer-overflow only triggers above 64 KB.
