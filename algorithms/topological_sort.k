// Topological Sort (Kahn's algorithm)
// DAG stored as: graph env mapping node -> "neighbor1,neighbor2,...".
// Nodes are tracked separately so we can find isolated ones too.

func _ts_addEdge(graph, from, to) {
    let cur = envGet(graph, from)
    if len(cur) == 0 {
        emit envSet(graph, from, to)
    }
    let sb = sbNew()
    sb = sbAppend(sb, cur)
    sb = sbAppend(sb, ",")
    sb = sbAppend(sb, to)
    emit envSet(graph, from, sbToString(sb))
}

func _ts_addNode(nodes, n) {
    if len(nodes) == 0 { emit n }
    // Check if already in list
    let nc = count(nodes)
    let i = 0
    while i < nc {
        if split(nodes, i) == n { emit nodes }
        i += 1
    }
    let sb = sbNew()
    sb = sbAppend(sb, nodes)
    sb = sbAppend(sb, ",")
    sb = sbAppend(sb, n)
    emit sbToString(sb)
}

func topoSort(graph, nodes) {
    // 1. Compute in-degree for each node.
    let indeg = envNew()
    let nc = count(nodes)
    let i = 0
    while i < nc {
        indeg = envSet(indeg, split(nodes, i), "0")
        i += 1
    }
    i = 0
    while i < nc {
        let u = split(nodes, i)
        let neigh = envGet(graph, u)
        if len(neigh) > 0 {
            let mc = count(neigh)
            let j = 0
            while j < mc {
                let v = split(neigh, j)
                let cur = toInt(envGet(indeg, v))
                indeg = envSet(indeg, v, "" + (cur + 1))
                j += 1
            }
        }
        i += 1
    }

    // 2. Seed queue with all in-deg-0 nodes.
    let queue = ""
    let first = 1
    i = 0
    while i < nc {
        let u = split(nodes, i)
        if toInt(envGet(indeg, u)) == 0 {
            if first { first = 0 } else {
                let q1 = sbNew()
                q1 = sbAppend(q1, queue)
                q1 = sbAppend(q1, ",")
                queue = sbToString(q1)
            }
            let q2 = sbNew()
            q2 = sbAppend(q2, queue)
            q2 = sbAppend(q2, u)
            queue = sbToString(q2)
        }
        i += 1
    }

    // 3. Drain queue, decrementing in-degrees.
    let order = ""
    let firstO = 1
    while len(queue) > 0 {
        let u = split(queue, 0)
        let qn = count(queue)
        if qn > 1 {
            let nq = sbNew()
            let k = 1
            while k < qn {
                if k > 1 { nq = sbAppend(nq, ",") }
                nq = sbAppend(nq, split(queue, k))
                k += 1
            }
            queue = sbToString(nq)
        } else {
            queue = ""
        }
        if firstO { firstO = 0 } else {
            let o1 = sbNew()
            o1 = sbAppend(o1, order)
            o1 = sbAppend(o1, ",")
            order = sbToString(o1)
        }
        let o2 = sbNew()
        o2 = sbAppend(o2, order)
        o2 = sbAppend(o2, u)
        order = sbToString(o2)

        let neigh = envGet(graph, u)
        if len(neigh) > 0 {
            let mc = count(neigh)
            let j = 0
            while j < mc {
                let v = split(neigh, j)
                let d = toInt(envGet(indeg, v)) - 1
                indeg = envSet(indeg, v, "" + d)
                if d == 0 {
                    let q3 = sbNew()
                    q3 = sbAppend(q3, queue)
                    if len(queue) > 0 { q3 = sbAppend(q3, ",") }
                    q3 = sbAppend(q3, v)
                    queue = sbToString(q3)
                }
                j += 1
            }
        }
    }
    emit order
}

just run {
    kp("Topological Sort (Kahn's)")
    kp("=========================")
    // Example: courses with prerequisites.
    //   intro -> data, intro -> math
    //   data  -> algo
    //   math  -> algo
    //   algo  -> capstone
    let g = envNew()
    g = _ts_addEdge(g, "intro", "data")
    g = _ts_addEdge(g, "intro", "math")
    g = _ts_addEdge(g, "data",  "algo")
    g = _ts_addEdge(g, "math",  "algo")
    g = _ts_addEdge(g, "algo",  "capstone")

    let nodes = ""
    nodes = _ts_addNode(nodes, "intro")
    nodes = _ts_addNode(nodes, "data")
    nodes = _ts_addNode(nodes, "math")
    nodes = _ts_addNode(nodes, "algo")
    nodes = _ts_addNode(nodes, "capstone")

    kp("  order: " + topoSort(g, nodes))
}
