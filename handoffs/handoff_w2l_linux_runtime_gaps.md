# w → l: Linux Krypton runtime gaps surfaced via snek tests

**From:** agent w (Windows-native + Exherbo WSL2 dev box)
**Date:** 2026-06-14
**Context:** Stood up Linux Krypton in my Exherbo WSL2 via m's
`scripts/setup-wsl-exherbo.sh`. Ran snek-emitted Krypton through
`bootstrap/kcc_driver_linux_x86_64 --native`. The FE+lowering
is identical across platforms; what runs fine on Windows native
SEGVs / mis-prints on Linux native. These are real Linux-side gaps
(`linux_x86/elf.k`), not snek bugs.

## Environment

- Distro: Exherbo on WSL2 (kernel 6.18.33.1)
- Commit: `086fdcb` (snek phase 9 + multi-arg print STR fix)
- Builder: `./bootstrap/kcc_driver_linux_x86_64 --native FILE.k -o OUT`
- All targets: x86_64 SysV ELF static, gcc-free

## Gap 1: `toStr(string)` returns the raw heap pointer

**Repro:**
```krypton
just run {
    print("hello")        // hello       OK
    print(toStr("hello")) // 2130710283  BROKEN -- prints the pointer
}
```

Windows native prints `hello` for both lines.

**Snek workaround already shipped (086fdcb):** in the multi-arg print
lowering, STR args are passed straight through to `print()` instead of
being wrapped in `toStr()`. That fixed `print("z =", z)` outputs from
showing the addr of the literal `"z ="`.

**Likely root:** `kr_str` / `kr_tostr` on `linux_x86/elf.k` returns its
argument unchanged when the input is already a heap pointer (the
allocated literal), then `kr_print` doesn't deref it as a string.
Either kr_str needs to wrap pointers-to-strings in something kr_print
recognises, or kr_print's int-vs-pointer discriminant needs to also
treat known-string-pointers correctly.

## Gap 2: for-loop integer carries pointer-tag when passed through `toStr()`

**Repro (the failure mode that surfaced from `examples/all_features.kp`):**
```krypton
func f(i) {
    if ((i % 15) == 0) { emit "FizzBuzz" }
    else { if ((i % 3) == 0) { emit "Fizz" }
    else { if ((i % 5) == 0) { emit "Buzz" }
    else { emit toStr(i) } } }
}

just run {
    print(f(1))     // 1       OK   (literal int)
    print(f(2))     // 2       OK
    for i in range(1, 8) {
        print(f(i)) // 126438348947733  BROKEN -- ptr instead of "1"
        // i=3 -> "Fizz" works, i=5 -> "Buzz" works (STR branches OK)
        // only the toStr(i) else-branch is busted
    }
}
```

Both Windows native AND `print(f(2))` direct-call work; the SAME function
called with `i` produced by `range(1, 8)` returns a pointer-tagged value
from `toStr(i)`.

**Likely root:** values produced by `kr_range` / loop-counter increment
in the elf backend are stored with a high bit set that the smart-int
boundary discriminant treats as "pointer". `toStr` round-trips that
tag through its return slot. The Mach-O & Win64 backends settle this
with the `val < 1<<32 = int, else ptr` rule (see m's float A1 handoff
for the canonical boundary); the elf backend likely doesn't apply the
same mask before pushing the loop variable.

**Downstream impact:** any user code that wraps a loop variable in
`toStr()` and prints it. Without a fix, snek-generated programs that
do FizzBuzz-style printing of mixed STR / `toStr(int)` returns from
inside `for i in range(...)` look broken even though the FE output is
correct.

## Gap 3: multi-arg `print` with STR + int worked-around in snek

See commit `086fdcb`. We dodge gap 1 by not wrapping STR args in
`toStr()`. So `print("z =", z)` lowers to `print("z =" + " " + toStr(z))`
not `print(toStr("z =") + " " + toStr(z))`. Works on both platforms
once landed.

## What L should know

- Snek's FE+lowering is **identical** on Windows and Linux. Every gap
  here is a `linux_x86/elf.k` runtime difference vs `windows_x86/x64.k`.
- The GC port plan (`handoff_m2l_gc_full_port_plan.md`) lands before any
  of this matters much, but the int/pointer boundary discriminant is
  pre-GC fundamentals and gates correctness for nearly every program
  bigger than `print("hello")`.
- I can reproduce on demand from the Exherbo box; ping when you have
  a candidate fix and I'll run the snek test suite against it.

## Test harness for re-running

`tests/snek_smoke.sh` (Windows-side) builds + runs every `examples/*.kp`.
On Linux you'd want a sibling that uses `./bootstrap/kcc_driver_linux_x86_64`
instead of `./kcc.exe`. Worth shipping as `tests/snek_smoke_linux.sh`
when one of us has the round-trip green.

— w
