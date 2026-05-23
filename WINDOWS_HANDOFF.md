# Windows Native Backend — Missing Builtins Handoff

**Date:** 2026-05-22  
**File to edit:** `compiler/windows_x86/x64.k` (~8108 lines)  
**Context:** macOS arm64 backend (`compiler/macos_arm64/macho_arm64_self.k`) gained 7 new builtins this week. Windows x64 already has `fromCharCode` (it's `kr_fromcharcode` in KRRT_FUNCS). The remaining 6 need to be added.

---

## The 6 Missing Builtins

| Krypton name | Krypton dispatch string | New runtime name | Args |
|---|---|---|---|
| `mapHas`   | `"mapHas"`   | `kr_maphas`   | `(map, key)` → `"0"` / `"1"` |
| `mapGet`   | `"mapGet"`   | `kr_mapget`   | `(map, key)` → value string or `""` |
| `mapSet`   | `"mapSet"`   | `kr_mapset`   | `(map, key, value)` → new map string |
| `exec`     | `"exec"`     | `kr_exec`     | `(cmd)` → stdout string |
| `shellRun` | `"shellRun"` | `kr_shellrun` | `(cmd)` → `"0"` (runs cmd, discards output) |
| `readLine` | `"readLine"` | `kr_readline` | `(prompt)` → line string (stdin, \n stripped) |

---

## Step 1 — Add to KRRT_FUNCS (line 456)

`KRRT_FUNCS` is a comma-separated string of all Krypton runtime function names. Append the 6 new names to the end of the existing string:

```
...kr_inttoptr"
```
→
```
...kr_inttoptr,kr_maphas,kr_mapget,kr_mapset,kr_exec,kr_shellrun,kr_readline"
```

---

## Step 2 — Add dispatch entries (around line 988-1002)

The dispatch block around lines 875–1002 maps Krypton builtin name strings to runtime function names. Add these 6 entries just before the final `emit name` at line 1002:

```krypton
    if name == "mapHas"    { emit "kr_maphas" }
    if name == "mapGet"    { emit "kr_mapget" }
    if name == "mapSet"    { emit "kr_mapset" }
    if name == "exec"      { emit "kr_exec" }
    if name == "shellRun"  { emit "kr_shellrun" }
    if name == "readLine"  { emit "kr_readline" }
```

---

## Step 3 — Implement each function in the runtime block

The runtime block starts around line 4000+. Each function follows this pattern:

```krypton
    offsets = offsets + "kr_FUNCNAME:" + pos + "\n"
    // ... hexByte/hexDword sequences ...
    pos = pos + TOTAL_BYTES
```

**Win64 ABI reminder:**
- Args in order: RCX, RDX, R8, R9 (then stack)
- Caller allocates 32-byte shadow space: `sub rsp, 0x28` at entry, `add rsp, 0x28` before ret
- RAX = return value
- Callee-saved: RBX, RBP, R12–R15 (save/restore if used)
- Internal calls: compute relative offset as `target_pos - (current_pos + 5)` for near call

**HeapAlloc pattern** (used by fromCharCode — see line 4208):
```
sub rsp, 0x28        ; 48 83 EC 28
; set up args in RCX/RDX/R8
call kr_heapalloc    ; E8 <rel32>
add rsp, 0x28        ; 48 83 C4 28
ret                  ; C3
```
`kr_heapalloc` is at a fixed offset computed earlier in the runtime blob (see `pos` tracking). Use the same `target - (current+5)` formula.

**atoi helper** (kr_toint pattern, used by fromCharCode): converts string in RCX to integer in RAX. Offset at the `kr_toint` entry in the offsets table.

---

### 3a. mapHas

**Semantics:** Map format is a flat comma-delimited string: `"key1,val1,key2,val2,..."` — keys and values alternate, separated by `,`. mapHas scans keys (positions 0, 2, 4, ...) for an exact match. Returns string `"1"` if found, `"0"` if not.

**Signature:** `kr_maphas(RCX=map_ptr, RDX=key_ptr) → RAX=string("0"/"1")`

**Algorithm:**
1. Walk map byte-by-byte comparing with key at each token boundary
2. Token boundary = start of string or byte after a `,`
3. If key matches exactly (next map byte is `,` or `\0`), it's a key match → return `"1"`
4. Skip that key's value (advance past next `,`), then repeat
5. If `\0` reached without match → return `"0"`

Return value must be a heap-allocated string `"1\0"` or `"0\0"` (2 bytes). Use `kr_heapalloc(2)` then write the char + null.

**Reference:** See ARM64 implementation at `macho_arm64_self.k:3557–3599` (32 instructions, pure string scan, no syscalls).

---

### 3b. mapGet

**Semantics:** Same map format. Find key → return its value (the next token). If not found, return `""` (empty string — a 1-byte heap allocation containing just `\0`).

**Signature:** `kr_mapget(RCX=map_ptr, RDX=key_ptr) → RAX=value_string`

**Algorithm:**
1. Walk tokens in pairs (key, value)
2. On key match: scan forward past the `,`, then copy the value token into a new heap allocation until the next `,` or `\0`
3. On no match: allocate 1 byte, write `\0`, return it

**Reference:** ARM64 `macho_arm64_self.k:3689–3762` (93 instructions).

---

### 3c. mapSet

**Semantics:** Same map format. If key exists, replace its value. If not, append `",key,value"`. Returns the new map string (heap-allocated).

**Signature:** `kr_mapset(RCX=map_ptr, RDX=key_ptr, R8=value_ptr) → RAX=new_map_string`

**Algorithm:**
1. Walk map tokens to find key
2. If found: build new string = prefix up to start of old value + new value + rest after old value
3. If not found: `strlen(map) + 1 + strlen(key) + 1 + strlen(value) + 1` bytes; copy map, append `,key,value`

This is the most complex of the three. The ARM64 version is 150 instructions. On x64 you can call `kr_len` (already in runtime) to get string lengths, or inline the strlen loop. Calling `kr_heapalloc` for the new buffer is simplest.

**Reference:** ARM64 `macho_arm64_self.k:3763–3912` (150 instructions).

---

### 3d. shellRun

**Semantics:** Run `cmd` via the shell. Does NOT capture output — stdout goes to the terminal. Returns `"0"` always.

**Signature:** `kr_shellrun(RCX=cmd_ptr) → RAX=string("0")`

**Windows implementation using CreateProcessA:**

```
kr_shellrun(RCX=cmd):
  sub rsp, 0x28 + sizeof(STARTUPINFOA) + sizeof(PROCESS_INFORMATION)
  ; Build command string: "cmd.exe /C " + cmd  (or use cmd directly via CreateProcessA lpCommandLine)
  ;
  ; Simplest: use CreateProcessA with lpApplicationName=NULL,
  ;   lpCommandLine = "cmd /C <cmd>" built in a local buffer, or
  ;   call _popen equivalent via CreateProcessA with bInheritHandles=FALSE, no pipes
  ;
  ; STARTUPINFOA: zero it, set cb=sizeof(STARTUPINFOA)=68
  ; CreateProcessA(NULL, cmdline, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)
  ; WaitForSingleObject(pi.hProcess, INFINITE=0xFFFFFFFF)
  ; CloseHandle(pi.hProcess); CloseHandle(pi.hThread)
  ; alloc 2 bytes, write "0\0", return
```

`CreateProcessA` is already in `KR32_FUNCS` (line 454). `WaitForSingleObject` and `CloseHandle` are also already there.

**IAT entry:** `CreateProcessA` is already imported — no new IAT entries needed for shellRun.

**Tip:** Build the `"cmd /C "` prefix inline (7 bytes of immediates onto the stack), then call a helper to concatenate with the cmd arg, or use a fixed stack buffer if cmd is known short. For a robust implementation, dynamically allocate a `"cmd /C " + cmd` string.

---

### 3e. exec

**Semantics:** Run `cmd` via the shell, **capture stdout** as a string. Returns the captured output.

**Signature:** `kr_exec(RCX=cmd_ptr) → RAX=output_string`

**Windows implementation using pipes:**

```
kr_exec(RCX=cmd):
  ; 1. CreatePipe(&hReadPipe, &hWritePipe, NULL, 0)
  ;    → hReadPipe (read end), hWritePipe (write end) on stack
  ; 2. STARTUPINFOA: zero it, set cb=68, dwFlags=STARTF_USESTDHANDLES=0x100,
  ;    hStdOutput=hWritePipe, hStdError=hWritePipe
  ; 3. CreateProcessA(NULL, "cmd /C <cmd>", NULL, NULL,
  ;                   TRUE, 0, NULL, NULL, &si, &pi)
  ; 4. CloseHandle(hWritePipe)  ← MUST close write end in parent or ReadFile never returns
  ; 5. Loop: ReadFile(hReadPipe, buf, bufsize, &bytesRead, NULL)
  ;    Accumulate into a growing heap buffer
  ; 6. WaitForSingleObject(pi.hProcess, INFINITE)
  ; 7. CloseHandle(pi.hProcess); CloseHandle(pi.hThread); CloseHandle(hReadPipe)
  ; 8. NUL-terminate buffer, return it
```

`CreatePipe`, `ReadFile`, `CreateProcessA`, `WaitForSingleObject`, `CloseHandle` are all already in `KR32_FUNCS`.

**IAT:** No new imports needed.

**Note:** `PeekNamedPipe` is also already imported if you want non-blocking reads.

---

### 3f. readLine

**Semantics:** Print `prompt` to stdout, read one line from stdin, strip trailing `\n`. Returns the line as a string.

**Signature:** `kr_readline(RCX=prompt_ptr) → RAX=line_string`

**Windows implementation:**

```
kr_readline(RCX=prompt):
  ; 1. strlen(prompt) — inline or call kr_len
  ; 2. WriteFile(GetStdHandle(-11), prompt, len, &written, NULL)
  ;    STD_OUTPUT_HANDLE = -11 = 0xFFFFFFF5
  ; 3. Alloc 4096-byte buffer via kr_heapalloc(4096)
  ; 4. ReadFile(GetStdHandle(-10), buf, 4096, &bytesRead, NULL)
  ;    STD_INPUT_HANDLE = -10 = 0xFFFFFFF6
  ; 5. Strip trailing \r\n (Windows console adds \r\n)
  ;    Strip last byte if '\n', then strip last byte if '\r'
  ; 6. NUL-terminate, return buf
```

`GetStdHandle`, `WriteFile`, `ReadFile` already in `KR32_FUNCS`.

**Key difference from macOS:** Windows console sends `\r\n` on Enter. Strip both.

---

## Step 4 — Rebuild kcc-arm64… wait, wrong platform

On Windows you rebuild `kcc.exe` / the Windows native compiler. The build command depends on your Windows build setup. Typically:

```
kcc.sh kcc.sh --native -o kcc_new.exe compiler/compile.k
```

or whatever the Windows bootstrap sequence is.

---

## Quick Reference: Common x86-64 encodings

```
sub rsp, 0x28        48 83 EC 28
add rsp, 0x28        48 83 C4 28
ret                  C3
mov rcx, rax         48 89 C1
mov rdx, rax         48 89 C2
mov r8, rax          49 89 C0
push rbx             53
pop rbx              5B
mov rbx, rax         48 89 C3
xor eax, eax         33 C0       (zero rax, preferred for flag clearing)
call rel32           E8 <4 bytes little-endian signed offset from end of call instr>
```

---

## Testing

Use `tests/test_to_int.k` as a template. Add a `tests/test_map.k` and `tests/test_exec.k`:

```krypton
just run {
    let m = "a,1,b,2"
    assert mapHas(m, "a") == "1"
    assert mapHas(m, "x") == "0"
    assert mapGet(m, "b") == "2"
    assert mapGet(m, "x") == ""
    let m2 = mapSet(m, "c", "3")
    assert mapHas(m2, "c") == "1"
    assert mapGet(m2, "c") == "3"
    let out = exec("echo hello")
    assert startsWith(out, "hello")
    kp("all map/exec tests passed")
}
```

---

## What macOS already has (for reference diff)

The ARM64 backend gained these 7 new builtins this week:
- `fromCharCode` — already existed in Windows (`kr_fromcharcode`)
- `readLine`, `shellRun`, `exec`, `mapHas`, `mapGet`, `mapSet` — the 6 listed above

All tested and working in macOS native with `homebrew-analytics/run.k`.
