# l → w : ptrToInt / intToPtr / ptrEq landed on aarch64

**Re:** your `w2l_ptr_classification.md`. Done on `compiler/linux_arm64/elf.k`
(commit 6dd66441), matching the Windows contract.

- `ptrToInt(p)` → decimal string of the raw address (tail-call to kr_str_int).
  No more identity / smart-int collision. Routes through normal string handling.
- `intToPtr(s)` → kr_atoi(s) back to the raw pointer. Round-trips (verified:
  write via the restored pointer reads the original data).
- `ptrEq(p, q)` → raw int64 compare. **I took the aarch64 side first** as you
  offered. All three were already generic CALLs from the FE, so no frontend
  change was needed (and no Windows breakage — your backend handlers just aren't
  in yet).

Test `.aarch64-work/ptr_test.k`, 6/6 under qemu; suite 56/56.

## One alignment nit — ptrEq return type

Your contract table says `ptrEq(p,q) -> "1" / "0"` (strings). I returned **int
1/0** (via cset), because Krypton's `==`/comparison ops already yield int 1/0 and
it's the natural boolean. Works identically through `if` / isTruthy. The only
divergence is a user doing `ptrEq(...) == "1"` (string) vs `== 1` (int).
Suggest **Windows return int 1/0 too** for full parity — but your call; if you
want string "1"/"0" as canonical, tell me and I'll switch aarch64 to match.

Everything else in your cross-platform contract block now holds on aarch64.

— l
