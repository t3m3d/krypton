// Singly-linked list ops
// Each node lives in a global env that maps a node id (string) to its
// {value, next} pair. We use env-of-env: list-env is one env, with each
// node-id mapped to a small string "value:V,next:N".
//
// This is a stress test for the native env runtime — every push/pop/reverse
// touches envSet/envGet repeatedly.
//
// Note: helpers don't use the "id;envPtr" pair-encoding trick — env heads are
// heap pointers, not NUL-terminated strings, so kr_concat would corrupt them.
// Instead we keep the id counter inside the env itself ("next_id" field).

func _ll_findColon(s) {
    let i = 0
    while i < len(s) {
        if s[i] == ":" { emit i }
        i += 1
    }
    emit -1
}

func _ll_node(value, next) {
    let sb = sbNew()
    sb = sbAppend(sb, "value:")
    sb = sbAppend(sb, value)
    sb = sbAppend(sb, ",next:")
    sb = sbAppend(sb, next)
    emit sbToString(sb)
}

func _ll_field(node, name) {
    // Tiny inline parser for "value:V,next:N" → field by name.
    let nc = count(node)
    let i = 0
    while i < nc {
        let part = split(node, i)
        let c = _ll_findColon(part)
        if c >= 0 {
            let key = substring(part, 0, c)
            if key == name {
                emit substring(part, c + 1, len(part))
            }
        }
        i += 1
    }
    emit ""
}

// Storage holds:
//   "head" -> id of first node (or "")
//   "next_id" -> integer id counter as a string
//   "<id>" -> node string

func newList() {
    let s = envNew()
    s = envSet(s, "head", "")
    s = envSet(s, "next_id", "0")
    emit s
}

// Returns just the next id as a string; caller bumps next_id afterwards.
func _ll_nextId(store) {
    emit envGet(store, "next_id")
}

func _ll_bumpId(store) {
    let cur = toInt(envGet(store, "next_id"))
    emit envSet(store, "next_id", "" + (cur + 1))
}

func pushFront(store, value) {
    let id = _ll_nextId(store)
    let s = _ll_bumpId(store)
    let head = envGet(s, "head")
    s = envSet(s, id, _ll_node(value, head))
    emit envSet(s, "head", id)
}

func pushBack(store, value) {
    let id = _ll_nextId(store)
    let s = _ll_bumpId(store)
    s = envSet(s, id, _ll_node(value, ""))
    let head = envGet(s, "head")
    if len(head) == 0 {
        emit envSet(s, "head", id)
    }
    // Walk to last node, update its next.
    let cur = head
    let cont = 1
    while cont {
        let node = envGet(s, cur)
        let nxt = _ll_field(node, "next")
        if len(nxt) == 0 { cont = 0 }
        if cont { cur = nxt }
    }
    let lastNode = envGet(s, cur)
    let lastVal = _ll_field(lastNode, "value")
    emit envSet(s, cur, _ll_node(lastVal, id))
}

func toList(store) {
    let head = envGet(store, "head")
    if len(head) == 0 { emit "" }
    let sb = sbNew()
    let cur = head
    let first = 1
    let cont = 1
    while cont {
        let node = envGet(store, cur)
        if len(node) == 0 { cont = 0 }
        if cont {
            if first { first = 0 } else { sb = sbAppend(sb, ",") }
            sb = sbAppend(sb, _ll_field(node, "value"))
            let nxt = _ll_field(node, "next")
            if len(nxt) == 0 { cont = 0 }
            if cont { cur = nxt }
        }
    }
    emit sbToString(sb)
}

// `length` and `reverse` are both built-in function names (aliased
// to count and the new string-reverse op respectively), so we use
// `listLength`/`listReverse` to avoid being shadowed at call sites.
func listLength(store) {
    let head = envGet(store, "head")
    if len(head) == 0 { emit 0 }
    let n = 0
    let cur = head
    let cont = 1
    while cont {
        let node = envGet(store, cur)
        if len(node) == 0 { cont = 0 }
        if cont {
            n += 1
            let nxt = _ll_field(node, "next")
            if len(nxt) == 0 { cont = 0 }
            if cont { cur = nxt }
        }
    }
    emit n
}

func listReverse(store) {
    let head = envGet(store, "head")
    if len(head) == 0 { emit store }
    // Iterative pointer-flip: walk forward, set each node's next to previous.
    let prev = ""
    let cur = head
    let cont = 1
    while cont {
        let node = envGet(store, cur)
        let nxt = _ll_field(node, "next")
        let v = _ll_field(node, "value")
        store = envSet(store, cur, _ll_node(v, prev))
        prev = cur
        if len(nxt) == 0 { cont = 0 }
        if cont { cur = nxt }
    }
    emit envSet(store, "head", prev)
}

just run {
    kp("Singly-linked list (env-backed)")
    kp("===============================")

    let s = newList()
    s = pushBack(s, "a")
    s = pushBack(s, "b")
    s = pushBack(s, "c")
    s = pushBack(s, "d")
    kp("  push back a,b,c,d -> [" + toList(s) + "]   length=" + listLength(s))

    s = pushFront(s, "z")
    kp("  push front z       -> [" + toList(s) + "]   length=" + listLength(s))

    s = listReverse(s)
    kp("  reverse            -> [" + toList(s) + "]")

    let empty = newList()
    kp("  empty list         -> [" + toList(empty) + "]   length=" + listLength(empty))
}
