// Union-Find (Disjoint Set Union)
// Stored as env: node -> parent.
//
// Note: path compression would normally rewrite parent pointers during find.
// That requires returning two values (root, updated env) from a single Krypton
// function — and Krypton's "" pair-encoding trick only works when both halves
// are NUL-terminated strings. Env heads are heap pointers, not strings, so
// `root + ";" + envPtr` corrupts when kr_concat tries to read the pointer as a
// C-string. We therefore use plain find without compression. O(n) per find;
// fine for small graphs.

func _uf_make(node, parents) {
    if len(envGet(parents, node)) > 0 { emit parents }
    emit envSet(parents, node, node)
}

func _uf_find(node, parents) {
    let cur = node
    let cont = 1
    while cont {
        let par = envGet(parents, cur)
        if par == cur { cont = 0 }
        if cont { cur = par }
    }
    emit cur
}

func _uf_union(a, b, parents) {
    let ra = _uf_find(a, parents)
    let rb = _uf_find(b, parents)
    if ra == rb { emit parents }
    emit envSet(parents, ra, rb)
}

func _uf_connected(a, b, parents) {
    let ra = _uf_find(a, parents)
    let rb = _uf_find(b, parents)
    if ra == rb { emit "1" }
    emit "0"
}

just run {
    kp("Union-Find")
    kp("==========")
    let p = envNew()
    let names = "A,B,C,D,E,F"
    let n = count(names)
    let i = 0
    while i < n { p = _uf_make(split(names, i), p); i += 1 }

    p = _uf_union("A", "B", p)
    p = _uf_union("B", "C", p)
    p = _uf_union("D", "E", p)

    kp("  A~B = " + _uf_connected("A", "B", p))   // 1
    kp("  A~C = " + _uf_connected("A", "C", p))   // 1
    kp("  A~D = " + _uf_connected("A", "D", p))   // 0
    kp("  D~E = " + _uf_connected("D", "E", p))   // 1
    kp("  E~F = " + _uf_connected("E", "F", p))   // 0

    p = _uf_union("C", "D", p)
    kp("  after C~D union:")
    kp("  A~E = " + _uf_connected("A", "E", p))   // 1
    kp("  A~F = " + _uf_connected("A", "F", p))   // 0
}
