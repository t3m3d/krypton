// B3 slice append — cap-aware. append(s, v): if len < cap, write v in place
// into the shared backing (Go-style aliasing) and return a len+1 slice; else
// grow (new buffer, copy, append). Base handle never pointer-arithmetic'd.
// FE-lowered over the A5 buf builtins (labels/jumps + bufNew/bufGet/bufSet).
just run {
    let arr = array(8)
    let i = 0
    while i < 8 { arr[i] = i  i = i + 1 }     // arr = 0,1,2,3,4,5,6,7

    // ── in-place append: cap > len (obtained via reslice) ───────────────────
    let s = arr[2:6]            // len4 cap4 over arr[2..5] = 2,3,4,5
    let sub = s[0:2]            // len2 cap4 over arr[2..3] = 2,3 (spare cap)
    let g = append(sub, 99)    // len2 < cap4 -> in place, writes arr[4]
    if g.len != 3 { kp("[FAIL] in-place len"); exit("1") }
    if g[2] != 99 { kp("[FAIL] in-place value"); exit("1") }
    if arr[4] != 99 { kp("[FAIL] in-place aliases backing array"); exit("1") }
    if g[0] != 2 || g[1] != 3 { kp("[FAIL] in-place preserves head"); exit("1") }

    // ── grow append: len == cap forces a fresh buffer ───────────────────────
    let f = arr[2:6]           // len4 cap4 over arr[2..5] = 2,3,99,5 (arr[4]=99 now)
    let f2 = append(f, 77)     // len4 == cap4 -> grow, copy 4, append
    if f2.len != 5 { kp("[FAIL] grow len"); exit("1") }
    if f2.cap < 5 { kp("[FAIL] grow cap"); exit("1") }
    if f2[4] != 77 { kp("[FAIL] grow appended value"); exit("1") }
    if f2[0] != 2 || f2[2] != 99 || f2[3] != 5 { kp("[FAIL] grow copied head"); exit("1") }
    f2[0] = 1000               // fresh buffer -> must NOT alias arr
    if arr[2] != 2 { kp("[FAIL] grow must not alias original backing"); exit("1") }

    // ── chained append on the grown slice (cap headroom from *2) ────────────
    let f3 = append(f2, 55)    // f2 cap is 8, len 5 -> in place
    if f3.len != 6 || f3[5] != 55 { kp("[FAIL] chained append"); exit("1") }

    kp("[PASS] slice append (in-place within cap, grow on overflow, chained)")
}
