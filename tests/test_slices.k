// B3 slices — `s = arr[lo:hi]` builds a (ptr, len, cap) view over an A5 array.
// s[i] reads/writes the underlying array (aliasing); s.len/s.cap read the
// triple; reslice s[a:b] sub-views without copying. FE-lowered over the A5 buf
// builtins (8-byte slots, int/pointer). No backend change. append: not yet
// (pairs with the GC freelist work).
just run {
    let arr = array(8)
    let i = 0
    while i < 8 { arr[i] = i * 10  i = i + 1 }   // 0,10,20,30,40,50,60,70

    let s = arr[2:6]                 // view of arr[2..5] -> 20,30,40,50
    if s.len != 4 { kp("[FAIL] slice len"); exit("1") }
    if s.cap != 4 { kp("[FAIL] slice cap"); exit("1") }
    if s[0] != 20 { kp("[FAIL] slice read s[0]"); exit("1") }
    if s[3] != 50 { kp("[FAIL] slice read s[3]"); exit("1") }

    s[1] = 999                       // writes through to arr[3]
    if s[1] != 999 { kp("[FAIL] slice write readback"); exit("1") }
    if arr[3] != 999 { kp("[FAIL] slice write aliases underlying array"); exit("1") }

    let sub = s[1:3]                 // reslice -> arr[3..4] -> 999,40
    if sub.len != 2 { kp("[FAIL] reslice len"); exit("1") }
    if sub.cap != 3 { kp("[FAIL] reslice cap = parent.cap - lo (4-1)"); exit("1") }
    if sub[0] != 999 { kp("[FAIL] reslice read aliases parent"); exit("1") }
    if sub[1] != 40 { kp("[FAIL] reslice read sub[1]"); exit("1") }

    kp("[PASS] slices (create, len/cap, index r/w aliasing, reslice)")
}
