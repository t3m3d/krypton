# Krypton 2.0 — quick reference

A two-page cheat sheet for everything new in 2.0. For deeper dives see
`gc_user_guide.md`, `imports.md`, `spec/`, and `CHANGELOG.md`.

## GC

```krypton
gcCollect()                // mark + sweep, returns sweep count (string)
gcWalkAllocs()             // current live alloc count
gcFreelistCount()          // chunks waiting for reuse
gcAllocCount()             // monotonic total allocs (incl. reuses)
gcAllocated()              // total bytes ever allocated
gcLimit()  /  gcSetLimit(n)// soft byte limit; ExitProcess(99) on overrun

// Lower-level building blocks (don't call separately — see gc_user_guide.md)
gcMark()                   // mark phase only
gcSweep()                  // sweep phase only
```

Call `gcCollect()` between event-loop iterations in long-running programs.

## Lambdas + closures

```krypton
let n = 5
let times = func(x) { emit toInt(x) * n }   // captures `n`
print(times(7))                              // → 35

import "k:fp"
let xs = "1,2,3,4"
let doubled = fpMap(xs, func(x) { emit toInt(x) * 2 })
let evens   = fpFilter(xs, func(x) { emit toInt(x) % 2 == 0 })
let sum     = fpReduce(xs, "0", func(acc, x) { emit toInt(acc) + toInt(x) })

// Snapshot semantics — capture is by value at lambda creation:
let m = 5
let h = func(x) { emit x + m }
print(h(0))    // → 5
m = 100
print(h(0))    // → 5 (still captured 5)
```

## Typed pointers

```krypton
let p: *u8 = "hello"
print(p[0])      // → 104 ('h')

// Struct layout (declared via jxt or struct keyword)
struct Vec3 {
    field x i32
    field y i32
    field z i32
}

let v: *Vec3 = bufNew(sizeOf("Vec3"))
v.x = 1
v.y = 2
v.z = 3
print(v.x + v.y + v.z)   // → 6

// Heap-backed stack-shaped alloc:
let local Vec3 t
t.x = 5
```

## Win32 direct calls

```krypton
import "head:process"
import "head:windows"

Sleep(500)                              // 500ms; no cfunc wrapper needed
let t = GetTickCount()                  // returns DWORD as Krypton string
let pid = GetCurrentProcessId()
print("pid=" + pid)

// Registry
let HKLM = 2147483650
let KEY_READ = 131097
let phResult = bufNew(8)
RegOpenKeyExA(HKLM, "Software\\...", 0, KEY_READ, phResult)
RegCloseKey(bufGetQword(phResult, 0))
```

## Memory-mapped files

```krypton
import "k:mmap"

let m = mmapFile("big.log")
if mmapOk(m) == "1" {
    let p = mmapPtr(m)
    print(bufGetByte(p, 0))    // first byte
    mmapClose(m)
}
```

## asm primitives

```krypton
let t0 = rdtsc()             // x86 cycle counter (high-res timing)
pause()                      // CPU pause hint (spinloop friendly)
mfence()                     // full memory barrier
lfence()                     // load barrier
sfence()                     // store barrier
```

## Imports

```krypton
import "k:fp"          // → <root>/stdlib/fp.k
import "core:fp"       //   (alias for k:)
import "head:process"  // → <root>/headers/process.krh
import "headers:process"//  (alias for head:)
import "stdlib/foo.k"  // legacy path-relative form still works
```

## Pure functions (auto-checkpoint)

```krypton
func pure_format_event(seq) {
    // All allocs inside auto-reclaimed on return via gcCheckpoint/Restore
    let s = "[" + seq + "] " + seq
    let t = s + " end"
    emit t   // CAVEAT: explicit emit/return bypasses the restore
}
```

## Build

```
kcc -o foo.exe foo.k       # native PE/COFF, no gcc
kcc --ir foo.k > foo.kir   # emit IR
kcc --c foo.k > foo.c      # legacy C output
```

## Diagnostic flags

```
kcc --port-1to2 source.k   # scan for 1.x patterns needing migration
```
