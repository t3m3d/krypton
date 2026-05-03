// Dijkstra's Shortest Path
// Graph stored as env: node -> "neigh1:weight1,neigh2:weight2,...".
// Returns the distance from `src` to `dst`, or -1 if unreachable.

func _dj_findColon(s) {
    let i = 0
    while i < len(s) {
        if s[i] == ":" { emit i }
        i += 1
    }
    emit -1
}

func _dj_neighName(pair) {
    let c = _dj_findColon(pair)
    emit substring(pair, 0, c)
}

func _dj_neighWeight(pair) {
    let c = _dj_findColon(pair)
    emit toInt(substring(pair, c + 1, len(pair)))
}

func _dj_addEdge(graph, from, to, weight) {
    let cur = envGet(graph, from)
    let pair = sbNew()
    pair = sbAppend(pair, to)
    pair = sbAppend(pair, ":")
    pair = sbAppend(pair, weight)
    let entry = sbToString(pair)
    if len(cur) == 0 { emit envSet(graph, from, entry) }
    let sb = sbNew()
    sb = sbAppend(sb, cur)
    sb = sbAppend(sb, ",")
    sb = sbAppend(sb, entry)
    emit envSet(graph, from, sbToString(sb))
}

// "Priority queue" implemented as an unsorted env: node -> distance.
// Pop = scan for min. Linear, but simple and matches Krypton's idioms.
func _dj_popMin(dists, visited, nodes) {
    let nc = count(nodes)
    let bestN = ""
    let bestD = -1
    let i = 0
    while i < nc {
        let u = split(nodes, i)
        if envGet(visited, u) != "1" {
            let d = envGet(dists, u)
            if len(d) > 0 {
                let di = toInt(d)
                if bestD < 0 || di < bestD {
                    bestD = di
                    bestN = u
                }
            }
        }
        i += 1
    }
    emit bestN
}

func dijkstra(graph, nodes, src, dst) {
    let dists = envNew()
    dists = envSet(dists, src, "0")
    let visited = envNew()

    let cont = 1
    while cont {
        let u = _dj_popMin(dists, visited, nodes)
        if len(u) == 0 { cont = 0 }
        if cont {
            visited = envSet(visited, u, "1")
            if u == dst { cont = 0 }
            if cont {
                let du = toInt(envGet(dists, u))
                let neigh = envGet(graph, u)
                if len(neigh) > 0 {
                    let mc = count(neigh)
                    let j = 0
                    while j < mc {
                        let pair = split(neigh, j)
                        let v = _dj_neighName(pair)
                        let w = _dj_neighWeight(pair)
                        let nd = du + w
                        let cur = envGet(dists, v)
                        if len(cur) == 0 || nd < toInt(cur) {
                            dists = envSet(dists, v, "" + nd)
                        }
                        j += 1
                    }
                }
            }
        }
    }
    let dd = envGet(dists, dst)
    if len(dd) == 0 { emit -1 }
    emit toInt(dd)
}

func _dj_addNode(nodes, n) {
    if len(nodes) == 0 { emit n }
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

just run {
    kp("Dijkstra's Shortest Path")
    kp("========================")
    //   A --1-- B --2-- C
    //   |       |       |
    //   4       5       1
    //   |       |       |
    //   D --3-- E --1-- F
    let g = envNew()
    g = _dj_addEdge(g, "A", "B", 1)
    g = _dj_addEdge(g, "B", "A", 1)
    g = _dj_addEdge(g, "B", "C", 2)
    g = _dj_addEdge(g, "C", "B", 2)
    g = _dj_addEdge(g, "A", "D", 4)
    g = _dj_addEdge(g, "D", "A", 4)
    g = _dj_addEdge(g, "B", "E", 5)
    g = _dj_addEdge(g, "E", "B", 5)
    g = _dj_addEdge(g, "C", "F", 1)
    g = _dj_addEdge(g, "F", "C", 1)
    g = _dj_addEdge(g, "D", "E", 3)
    g = _dj_addEdge(g, "E", "D", 3)
    g = _dj_addEdge(g, "E", "F", 1)
    g = _dj_addEdge(g, "F", "E", 1)

    let nodes = ""
    nodes = _dj_addNode(nodes, "A")
    nodes = _dj_addNode(nodes, "B")
    nodes = _dj_addNode(nodes, "C")
    nodes = _dj_addNode(nodes, "D")
    nodes = _dj_addNode(nodes, "E")
    nodes = _dj_addNode(nodes, "F")

    kp("  A -> F = " + dijkstra(g, nodes, "A", "F"))   // 4 (A-B-C-F)
    kp("  A -> E = " + dijkstra(g, nodes, "A", "E"))   // 5
    kp("  A -> A = " + dijkstra(g, nodes, "A", "A"))   // 0
    kp("  C -> D = " + dijkstra(g, nodes, "C", "D"))   // 5
}
