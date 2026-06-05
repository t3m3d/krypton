# macOS self-host — clang-free (achieved 2026-06-03)

Krypton on macOS (Apple Silicon / arm64) builds, runs, and **self-hosts with
zero clang/gcc**. Verified end-to-end with a clang "tripwire" (a fake `clang`
on PATH that records any invocation): clang is **never** called for installing,
compiling, running, importing, or regenerating the compiler.

## What's native
- **Frontend** `compiler/macos_arm64/kcc-arm64` — `.k`/`.ks` → Krypton IR.
- **Backend** `compiler/macos_arm64/macho_host` — IR → Mach-O (arm64, `svc #0x80`
  syscalls, self-emitted load commands + ad-hoc SHA-256 code signature).
- **Seeds** `bootstrap/kcc_seed_macos_aarch64`, `bootstrap/macho_host_macos_aarch64`
  — the shipped native binaries; `build.sh`/`kcc.sh` copy them, never invoke a C
  compiler. (`macho_host` is gitignored — rebuilt from its seed per machine.)

## Verified (clang tripwired, never invoked)
- Clean-room install from seed → compile + run a program using `import "k:semver"`
  / `import "k:slug"` → correct output.
- Native toolchain regenerates BOTH seeds from source (`compile.k`,
  `macho_arm64_self.k`) in ~4 min.
- Self-host **fixpoint stable**: the regenerated frontend reproduces the
  frontend IR byte-for-byte (and the backend likewise).

## The bugs that were in the way (all fixed)
1. **dyld-cache heap cap** — the `__DATA` zero-fill heap maxed at `0x70000000`
   (the dyld shared cache sits just above). Fix: `__main__` mmaps an 8 GB anon
   heap and seeds the bump pointer with it.
2. **LINKEDIT/heap overlap** — `LINKEDIT_VADDR` was hardcoded `DATA+0x40000000`
   while DATA's vmsize is `0x70000000`. Aligned them.
3. **String ordering** — `LT/GT/LE/GE` compared raw pointers for string operands,
   so `charIsAlpha`'s `c>="a" && c<="z"` was garbage → the tokenizer dropped
   every identifier. Made ordering polymorphic (byte-wise strcmp for ptr operands).
4. **`>=2^32` vaddr literals** — the backend's `0x100000000` etc. crashed a
   native frontend's `toStr` (int/ptr magnitude tag). Replaced with their
   runtime-identical low-32 wrapped values (the code already supplies the high
   word via `hexQword2(lo,hi)`).
5. **O(n²) everywhere** — `tokAt` = `getLine` rescanned from the start (O(i)), so
   every token pass was O(n²) (~10 min on the backend). Added a pointer-keyed
   `getLine` cache (sequential access → O(1)). Plus: skip C-codegen in `--ir`
   mode, `irTypeOf`/`findInList` O(n). Step A: 10 min → 34 s.
6. **`environ()` no-op** — returned its arg, not the env value → `installRoot`
   wrong → imports didn't resolve → import binaries SIGILL'd. Fix: save `envp`
   (x2 from LC_MAIN) in `__main__`; `BUILTIN_ENVIRON` scans it.
7. Also fixed at the source while here: `trim` (all whitespace), `toLower`/
   `toUpper` (were no-ops), `exit()` codes (were a fixed bogus value).

## Still in-tree but unused on the native path (optional cleanup)
- `--gcc` C backend (the `kr_*` C runtime in `compile.k`), `cfunc` modules
  (`gui.k`, `server.k`), `bootstrap/kcc_seed.c`, `.krh` C-FFI headers.
- Full 64-bit user ints would need value tagging (`LOWBIT_TAGGING_PLAN.md`) —
  NOT required for clang-free; current ints are 32-bit-wrapping by design.
