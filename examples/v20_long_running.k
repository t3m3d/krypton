// 2.0 demo: long-running program that stays flat in memory.
//
// Without `gcCollect()`, this loop's per-iteration string allocations
// accumulate in the arena forever — Krypton 1.x would grow until OS
// limits or the soft `gcLimit` triggers.
//
// With 2.0's mark-sweep + freelist reuse, each `gcCollect()` returns
// the prior iteration's intermediates to the freelist. Each event is
// processed inside `processEvent()` so the function's exit pops all
// per-event shadow-stack roots — sweep then reclaims them on the next
// `gcCollect()`.
//
// Compare:
// - alloc_count grows monotonically (every alloc bumps it, including
//   reuses from the freelist)
// - live count stays bounded (per-event roots get popped on function
//   exit; gcCollect runs between events)

func processEvent(seq) {
    let stamp = "ts=" + seq
    let host  = "host=" + seq + ".local"
    let body  = stamp + " " + host
    let log1  = "[event] " + body
    let log2  = "  prev: " + log1
    let log3  = "  hash: " + seq + seq
    // No emit — event is "processed" via side effects (which here are
    // just allocations; in a real server they'd be socket writes).
}

just run {
    print("=== 2.0 long-running demo ===")
    print("Each event allocates ~6 strings; gcCollect() between events")
    print("")
    print("cycle | total  | live  | free")
    print("------+--------+-------+-----")

    let cycle = 0
    while cycle < 10 {
        processEvent(cycle)
        gcCollect()

        let total = gcAllocCount()
        let live  = gcWalkAllocs()
        let free  = gcFreelistCount()
        print(cycle + "    | " + total + "    | " + live + "   | " + free)
        cycle = cycle + 1
    }

    print("")
    print("done. Note: 'free' flatlines after cycle 1 — every event's")
    print("intermediate strings from a prior cycle get reused for the")
    print("current cycle's allocations. The slight 'live' growth comes")
    print("from this just-run loop's own per-iteration lets (cycle, total,")
    print("live, free) which accumulate in the loop's shadow stack until")
    print("just-run exits. A real long-running event-loop server would")
    print("see live count flat-line completely because the entire pump")
    print("body lives inside a function whose exit pops all shadow roots.")
}
