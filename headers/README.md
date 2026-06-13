# `headers/` — Krypton foreign-import declarations

`.krh` files declare functions, structs, and constants that live in
DLLs (Windows) or shared libraries (Linux / macOS). Krypton imports
them via `import "head:foo"` and the platform's native backend wires
the dispatch — direct IAT call on Windows, direct syscall or libc call
on POSIX.

**These are declaration-only files.** No `cfunc` blocks, no
implementation code. The function bodies live in the host OS's
binaries; we just describe their names + signatures so the compiler
can emit the right calling sequence.

## Convention (as of 2026-06-02)

Every header should:

1. **Start with a one-line summary** of what surface it binds.
2. **Name the DLL or library** it targets — e.g. `DLL: user32.dll`
   for Windows, `dylib: libobjc.dylib` for macOS, `lib: libc.so.6` for
   Linux. Multi-DLL grab bags list each.
3. **State the pipeline** — `native PE`, `native ELF`, `native Mach-O`,
   or `C-emit only` if the symbol isn't IAT-wired yet.
4. **Reference the IAT registration site** in the relevant backend
   (e.g. `compiler/windows_x86/x64.k` for Win32 DLLs).
5. **Not include `c "header.h"` or `t "header.h"` directives.** Those
   used to tell the deprecated `--gcc` C-emit path which `#include`
   to add. The native pipeline ignores them, and we're not adding new
   `--gcc` callers.

### Example shape

```krypton
// dwmapi.krh — Krypton bindings for the Desktop Window Manager API.
// Usage: import "head:dwmapi"
//
// DLL: dwmapi.dll
// Pipeline: native PE only — `kcc.sh -o win.exe app.k`.
//
// dwmapi.dll IAT slot was added to `compiler/windows_x86/x64.k`
// in Phase A (2026-05-11). Pure-Krypton callers can invoke these
// functions directly; the compiler emits an indirect CALL through
// the IAT entry with no `--gcc` C path involved.
//
// Declaration-only file. No `cfunc`, no `c "header.h"` includes.

jxt {
    func DwmSetWindowAttribute(hwnd, attribute, pvAttribute, cbAttribute)
    func DwmGetWindowAttribute(hwnd, attribute, pvAttribute, cbAttribute)
    func DwmExtendFrameIntoClientArea(hwnd, marginsInset)
    func DwmIsCompositionEnabled(pfEnabled)
    func DwmEnableBlurBehindWindow(hwnd, blurBehind)
}
```

## Current inventory (2026-06-02)

### Pure native — IAT or syscall, no C compiler in the loop

| Header | Platform | Target |
|---|---|---|
| `windows.krh` | Windows | kernel32 + advapi32 + pdh + psapi + shell32 |
| `user32.krh` | Windows | user32.dll |
| `gdi32.krh` | Windows | gdi32.dll |
| `comctl32.krh` | Windows | comctl32.dll |
| `comdlg32.krh` | Windows | comdlg32.dll |
| `dwmapi.krh` | Windows | dwmapi.dll |
| `uxtheme.krh` | Windows | uxtheme.dll |
| `iphlpapi.krh` | Windows | iphlpapi.dll |
| `process.krh` | Windows | kernel32 + shell32 |
| `fileio.krh` | Windows | kernel32.dll |
| `mmap.krh` | Windows | kernel32.dll |
| `winsock.krh` | Windows | ws2_32.dll *(IAT registered in x64.k 2026-06-13; x64_host_windows_x86_64.exe needs regen for runtime — see handoffs/handoff_w_ws2_32_iat.md)* |
| `shell32.krh` | Windows | shell32.dll *(IAT registered in x64.k 2026-06-13; x64_host_windows_x86_64.exe needs regen for runtime — pair with stdlib/shell.k)* |
| `psapi.krh` | Windows | psapi.dll *(IAT registered in x64.k 2026-06-13; x64_host_windows_x86_64.exe needs regen for runtime — pair with stdlib/proc_ex.k)* |
| `iphlpapi.krh` | Windows | iphlpapi.dll *(IAT registered in x64.k 2026-06-13; x64_host_windows_x86_64.exe needs regen for runtime — pair with stdlib/iphlp.k)* |
| `bcrypt.krh` | Windows | bcrypt.dll *(IAT registered in x64.k 2026-06-13; x64_host_windows_x86_64.exe needs regen for runtime — pair with stdlib/crypto.k)* |
| `wininet.krh` | Windows | wininet.dll *(IAT registered in x64.k 2026-06-13; x64_host_windows_x86_64.exe needs regen for runtime — pair with stdlib/httpc.k httpGetUrl/httpGetUrlStatus path)* |
| `objc.krh` | macOS | libobjc.dylib |
| `cocoa.krh` | macOS | Constants only — no DLL calls |

### Awaiting an IAT slot / syscall builtin

| Header | Platform | Status |
|---|---|---|
| `conio.krh` | Windows | `_kbhit`/`_getch` live in msvcrt.dll. Not yet IAT-wired. Use kernel32 console APIs instead. |
| POSIX headers (`sys_socket.krh`, `sys_stat.krh`, `fcntl.krh`, …) | Linux / macOS | Most still reference libc symbols. Agent m proved the path with direct-syscall builtins (`sockMake / Bind / Listen / …` in `compiler/macos_arm64/macho_arm64_self.k`). The same approach folds these headers into the native pipeline. |

### C-stdlib utilities (consider deprecating)

| Header | Reason to deprecate |
|---|---|
| `ctype.krh`, `string.krh`, `math.krh`, `stdio.krh`, `stdlib.krh` | Krypton already exposes `isDigit`, `toUpper`, `len`, `substring`, `floor`, `kp`, `exit`, etc. as builtins. The C-libc headers are vestigial. |

## Workflow for adding a new header

1. **Choose the import name** — `head:<short>` is the canonical form
   (e.g. `head:dwmapi`). Pick something concise; the filename should
   match (`headers/<short>.krh`).
2. **Pick the target binding mode:**
   - **Windows DLL** → add the function names to the relevant
     `KR*_FUNCS` list in `compiler/windows_x86/x64.k`. Add a new
     `KR<DLLNAME>_FUNCS` list + DLL descriptor if it's a fresh DLL.
     See the `gui.k` phase-A imports (2026-05-11 commit) for the
     pattern.
   - **macOS dylib** → wire the symbol resolution into
     `compiler/macos_arm64/macho_arm64_self.k`. Agent m's
     sock-builtin commits are the canonical reference.
   - **Linux syscall / shared library** → emit through
     `compiler/linux_x86/elf.k`. Agent l owns this surface.
3. **Write the `.krh` file** using the shape above. No `c "..."`
   directives. Add `// DLL:` / `// dylib:` / `// lib:` header.
4. **Smoke-test with `kcc.sh -o`** on the target platform.
5. **Update `docs/spec/functions.md`** with any new builtins, and
   this `headers/README.md` with the new entry.

## Why no C-include directives?

Historical: `jxt { c "windows.h" func CreateWindowExA(...) }` told
the `--gcc` C-emit path to drop `#include <windows.h>` into the
generated C source so the function declaration would resolve at link.

`--gcc` is deprecated in 2.2. The native pipeline does NOT need
those directives — it resolves the function name against its own IAT
tables (Windows) or syscall registry (Linux/macOS). Keeping them
around implied a C toolchain dependency and confused readers about
the build model.

If you ever DO need to use the C path for a header (for a temporary
escape hatch during porting), the include lines can be reintroduced
locally without committing them. But the long-term direction is no
C in the loop.

## Three-agent ownership

- **agent w (Windows):** owns all `.krh` files in this directory that
  target Windows DLLs. As of 2026-06-02 every Windows header in the
  table above except `conio.krh` is pure-native.
- **agent m (macOS):** owns `objc.krh`, `cocoa.krh`, and the in-flight
  macOS stdlib + header additions. Direct-syscall builtins
  (`sockMake / Bind / Listen / Accept / Recv / RecvStr / Send / Close`)
  shipped 2026-06-01 — see `compiler/macos_arm64/macho_arm64_self.k`.
- **agent l (Debian Linux):** owns the POSIX headers and the upcoming
  Linux-side direct-syscall builtin work that parallels agent m's
  macOS path. See `docs/claude/HANDOFF_LINUX_AGENT_L_2026_06_02.md`
  for the topology + which `kcc` to use.

Cross-platform headers (rare — most `.krh` files are platform-tagged)
should be coordinated through Brian.
