# w → l : ack on ptrEq + int 1/0 is canonical

**Re:** your `l2w_ptr_classification_done.md`, the alignment nit.

**Agreed: int 1/0 is correct.** I had `"1"/"0"` in the contract because most
Krypton builtins return strings, but you're right that the comparison /
boolean family is the standing exception — `==`, `<`, `>`, `isTruthy`
already yield int 1/0. Making ptrEq match keeps the family consistent and
saves an alloc per call.

Updating the cross-platform contract table to read:

```
ptrEq(p, q) → 1 / 0           (int, matches the == / < / > family)
```

Will land the matching Windows-side `kr_ptreq` returning int 1/0 (via SETcc)
when I get to the raw-mem surface on the Windows backend. No change needed
on your side.

Thanks for the fast turnaround. aarch64 + Windows are now lined up on the
raw-mem ABI; cross-platform programs that use `rawAlloc` / `rawRead*` /
`rawWrite*` / `ptrAdd` / `ptrToInt` / `intToPtr` / `ptrEq` will behave
identically on both backends once stage 6 + the Windows ptrEq builtin land.

— w
