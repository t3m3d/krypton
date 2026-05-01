# M1 MacBook session — adding/verifying arm64 support

Use this file as your morning checklist while at the doctor. ~2-3h target.

## State going in

`kompiler/macho.k` already has ~27 arm64 code branches (it was scaffolded for both x86_64 and arm64 from the start, but only x86_64 has been tested on real hardware — Tahoe Intel Mac, Apr 27). Memory note `project_macho_skeleton.md` documents what landed.

`verify_macho.sh` is a working Mach-O smoke test that handles both arches. It has two phases: hardcoded hello-world via `--hello-test`, and IR-driven from a real `.k` source.

So the real morning question is: **does the existing arm64 path actually work on M1, or is it stale?** Most of your time should go into running the test, finding the gap, and patching one thing at a time.

## Phase 1 — setup (~10 min)

```sh
# Clone (or pull if already cloned)
git clone https://github.com/t3m3d/krypton.git
cd krypton

# OR if you already have it:
git pull origin main

# Install Xcode CLT if you don't have it (provides clang, ld, otool, file)
xcode-select --install   # may already be installed; this is a no-op then

# Install Rosetta 2 (lets us also test x86_64 path on M1)
softwareupdate --install-rosetta --agree-to-license

# Build the bootstrap kcc
./build.sh
```

Expected: `./kcc` exists and `./build.sh test` reports passing tests.

If `./build.sh` fails, the bootstrap `kcc_seed_macos_arm64` may be missing. In that case, fall back to source-seed path:

```sh
clang -O2 -lm -w bootstrap/kcc_seed.c -o kcc
./kcc kompiler/compile.k > /tmp/_self.c
clang -O2 -lm -w /tmp/_self.c -o kcc
```

## Phase 2 — verify Mach-O smoke test (~15 min)

```sh
./verify_macho.sh --both
```

This compiles `kompiler/macho.k` to a host binary, then runs two phases per arch (hello-world hardcoded, and IR-driven). It will produce a clear PASS/FAIL summary at the bottom.

**Three outcomes:**

### Outcome A: both arches PASS

You're done with the high-bar goal — M1 is supported. Then:
- Run `examples_native2.sh` style sweep on macOS to see how many examples actually compile end-to-end through the macho path. There is no premade script; create one analogous to `tests/macho_smoke_test.sh` that loops over `examples/*.k` and runs each through `./kcc.sh --native`.
- Update `project_macho_skeleton.md` and `project_macbook_handoff.md` memory files with "arm64 verified on M1 <date>".
- Commit + push.

### Outcome B: x86_64 passes, arm64 fails

This is the most likely outcome. The arm64 path exists in macho.k but probably wasn't ever run on real arm64 hardware. Likely failures:

1. **Assembler error** — clang reports a syntax or instruction error in the emitted `.s`. Look at the .s file directly (`cat /tmp/krir_arm64.s`) and find the offending line. Cross-reference with `kompiler/macho.k`'s arm64 emission for that op.
2. **Link error** — symbol mismatch (e.g. `_main` vs `main`, or `_puts` vs `puts`). macOS uses underscore-prefixed symbols.
3. **Runtime crash** — assembled and linked but segfaults at runtime. arm64 ABI: x0..x7 are arg regs, x29 = frame pointer, x30 = link register, sp must stay 16-byte aligned at function call boundaries.
4. **Wrong output** — runs but prints wrong/empty string. Likely a relocation issue: arm64 uses `adrp` + `add` for PC-relative addressing, not RIP-relative like x86_64.

For each failure, fix one op at a time in `kompiler/macho.k`. The pattern is: find the `if arch == "arm64" { ... }` branch for the failing op, compare against ARM64 ABI docs, fix.

Useful one-liners for debug:
```sh
# Inspect emitted assembly
cat /tmp/krir_arm64.s

# Disassemble the binary
otool -tvV /tmp/krir_arm64

# Check what symbols the binary depends on
otool -L /tmp/krir_arm64
nm /tmp/krir_arm64
```

### Outcome C: build itself fails to even compile macho host

Means `kompiler/macho.k` has a Krypton-side bug (not arm64-specific). Read the error from `./kcc kompiler/macho.k`. Probably something compile.k tweaked recently doesn't agree with macho.k. Fix in macho.k, not compile.k.

## Phase 3 — keep going if Phase 2 was clean (~rest of time)

Stretch goals in priority order:

1. **Run `examples/*.k` sweep on macOS via the macho path.** Write a `mac_examples_sweep.sh` that mirrors `examples_native2.sh` but uses macOS clang. Record pass/fail. Most failures will be missing builtins (same list as Linux: `padLeft`, `padRight`, `tokenize`, etc. — see `project_elf_builtin_gaps.md`).

2. **Add `padLeft`/`padRight` to macho.k** — same way they'd be added to elf.k (separate per-op `arch == "arm64"` branches). 3-arg builtins. Used by ~7 examples. Plan in `project_doctor_session_plan.md` has the design notes (item 2).

3. **Performance benchmark on M1** — `time` fibonacci.k via the C path vs the macho path. M1 is fast; expect both to finish in milliseconds. The goal is to confirm the native path is at least as fast as gcc-built C.

## What NOT to do on M1 today

- Don't touch `kompiler/elf.k` (Linux backend).
- Don't touch `kompiler/x64.k` (Windows backend).
- Don't touch `kompiler/compile.k` unless you find a portability bug.
- Don't try to build `optimize_host` — it's only used by the Linux pipeline currently.
- Don't `git push --force`. Make a feature branch (`m1-arm64`) if your changes are big and you want to PR.

## Files you should read on M1 (in order)

1. This file (`M1_SETUP.md`)
2. `verify_macho.sh` (test runner)
3. `kompiler/macho.k` (the backend you'll be patching)
4. `kcc.sh` (driver — search for "PLATFORM == macos")
5. Memory files: `project_macho_skeleton.md`, `project_macho_tahoe_blocked.md`, `project_macbook_handoff.md`

## Reporting back

Before you leave the doctor's office:
- Make a short note of which Phase 2 outcome you got, what you fixed, and where you stopped.
- Append it to a new memory file, e.g. `project_m1_session_<date>.md`, so the Windows side can pick up later.
- Stage everything; commit and push so the desktop sees it.

Good luck. The arm64 branches in macho.k are real code — somebody (you, recently) wrote them — they just haven't been verified on hardware. Most likely you'll find one or two small instruction-encoding issues, fix them, and arm64 will work.
