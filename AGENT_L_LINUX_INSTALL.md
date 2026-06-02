# Agent L — install Krypton on Linux (ParrotOS / Debian)

Read this top to bottom. It is the only file you need to get Krypton built,
installed, and verified on a Debian-based box (ParrotOS, Kali, Ubuntu, Debian).
Your actual *task* (socket builtins) is at the bottom — install first.

---

## 0. What you are installing

Krypton is a self-hosting compiler. There is **no system package** — you build
from this repo. The pieces:

| thing | what it is |
|-------|-----------|
| `./kcc.sh` | **the driver — use this** (`kcc.sh file.k -o out`, `-r` run, `--ir`, `--c`, `--version`). v2.2.0. It detects OS/arch via `uname` and calls the right frontend binary. |
| `./kcc` | symlink → `kcc.sh` (same driver, shorter name). `kcc` and `kcc.sh` are interchangeable. NOT a separate dispatcher, NOT macOS-only. |
| `compiler/linux_x86/kcc-x64` | the actual Linux x86_64 frontend **binary** (what kcc.sh calls; built/seeded by `build.sh`) |
| `compiler/linux_x86/elf.k` | Linux native backend (emits ELF, no libc) — **this is what you'll edit** |
| `bootstrap/kcc_seed_linux_x86_64` | prebuilt seed binary → install needs **no gcc** |
| `stdlib/*.k` | importable modules (`import "k:name"`) |

Native pipeline on Linux: `.k → IR → elf.k → ELF binary`. No gcc at
user-invocation time. gcc is needed **only once** if you edit `elf.k` (see §4).

---

## 1. Prerequisites

```bash
sudo apt update
sudo apt install -y git build-essential
```

- `git` — clone the repo.
- `build-essential` — gives you `gcc`. **Not needed to install** (a prebuilt
  seed is shipped), but **needed to rebuild `elf.k`** after you edit it, which
  is your task. Install it now.
- Architecture: this ships prebuilt seeds for **x86_64** and **aarch64**.
  Check yours: `uname -m` → `x86_64` (most likely) or `aarch64`. Both work.

---

## 2. Clone

```bash
git clone https://github.com/t3m3d/krypton.git
cd krypton
```

If you already have it: `git pull` to get the latest (Agent M + W push here).

---

## 3. Build + install

```bash
./install.sh
```

That runs `./build.sh` (copies the prebuilt seed → `compiler/linux_x86/kcc-x64`,
smoke-tests `examples/fibonacci.k`) then symlinks `kcc` + `kcc.sh` into
`/usr/local/bin` (asks for sudo for the symlink only).

Expect:
```
  OK  prebuilt seed → compiler/linux_x86/kcc-x64
  OK  smoke test: fibonacci
installed:
  /usr/local/bin/kcc     -> .../krypton/kcc
  /usr/local/bin/kcc.sh  -> .../krypton/kcc.sh
```

**No-sudo / local install:** `./install.sh "$HOME/.local"` then make sure
`~/.local/bin` is on `PATH`.

**If `build.sh` says no prebuilt seed for your arch:** you're on something other
than x86_64/aarch64. Then it falls back to compiling `bootstrap/kcc_seed.c` with
gcc — that's why §1 installs build-essential. It still works, just needs gcc.

---

## 4. Verify

```bash
kcc.sh --version
echo 'just run { kp("hello from linux, no gcc") }' > /tmp/h.k
kcc.sh -r /tmp/h.k          # compile + run + delete
```

Should print `hello from linux, no gcc`. If it does, native ELF generation
works — you're installed.

Test an import too:
```bash
printf 'import "k:semver"\njust run { kp(toStr(semverCmp("1.2.0","1.10.0"))) }\n' > /tmp/s.k
kcc.sh -r /tmp/s.k          # expect -1
```

---

## 5. Editing the backend (`elf.k`) — the gcc-rebuild gotcha

When you change `compiler/linux_x86/elf.k`, `kcc.sh` must rebuild the backend
host. The native self-rebuild is blocked by a known elf.k self-host bug at
>66 funcs, so `kcc.sh` falls back to a **one-time gcc bootstrap** of `elf.k`
(this is why you need gcc installed even though install didn't). It happens
automatically on the next compile; you'll see:
```
kcc: rebuilding elf host (one-time gcc bootstrap...)
```
If gcc is missing here, you get `no prebuilt elf_host seed ... and no gcc found`
— fix by `sudo apt install build-essential`.

Verify after every elf.k edit: rebuild succeeds → recompile a `.k` →
**run it** (offset bugs in a backend show up as SIGILL/SIGSEGV at runtime, not
at compile time). Never commit an elf.k change you haven't run.

---

## 6. Your task

Socket builtins in `elf.k`, so `stdlib/server_native.k` serves HTTP C-free on
Linux (macOS is done, you mirror it). Full plan, syscall numbers, and the
3-edit discipline are in:

```
SOCKETS_CROSS_BACKEND_PLAN.md      (repo root — read the "Linux — TODO" section)
```

Linux is **Path A** there: inline `syscall` (`0F 05`), nr in RAX, args
RDI/RSI/RDX/R10/R8/R9; sockaddr_in has **no sin_len byte** (family at offset 0).
8 builtins: sockMake/Bind/Listen/Accept/Recv/Send/Close/RecvStr.

3 edits per builtin (skip one → SIGILL): (1) `compiler/compile.k` builtins list
~line 4199 + rebuild seed, (2) elf.k instruction-count table, (3) elf.k emit
block. Count MUST equal emitted instructions exactly.

---

## 7. Heads-up — broken native builtins (avoid in any Krypton you write)

Verified on the native backend; the macOS side hit all of these (likely same on
Linux native — confirm as you go):
- `toLower` / `toUpper` — **no-ops**. Inline ASCII case.
- `splitBy` / `split` (string) / `lines()` — **list values broken**. Use
  `indexOf`/`substring` scans + `getLine`/`lineCount`.
- `hex()` returns decimal — use `stdlib/hexenc.k`.
- `timestamp()` crashes `toStr`. Nested module imports don't link transitively
  (make modules self-contained).

Safe subset: `substring indexOf charCode fromCharCode(≤127) len toInt toStr
trim startsWith endsWith contains replace repeat sbNew/sbAppend/sbToString
arg/argCount getLine/lineCount kp`. Int adds wrap at 2^32.

---

## TL;DR

```bash
sudo apt install -y git build-essential
git clone https://github.com/t3m3d/krypton.git && cd krypton
./install.sh
kcc.sh -r <(echo 'just run { kp("ok") }')
# then read SOCKETS_CROSS_BACKEND_PLAN.md
```
