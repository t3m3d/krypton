// Graph DFS (Depth-First Search)

func addEdge(graph, from, to) {
    let neighbors = envGet(graph, from)
    if len(neighbors) == 0 {
        emit envSet(graph, from, to)
    }
    emit envSet(graph, from, neighbors + "," + to)
}

// Iterative DFS using a stack
just run {
    // Build a graph (same as BFS)
    let g = ""
    g = addEdge(g, "0", "1")
    g = addEdge(g, "0", "3")
    g = addEdge(g, "1", "0")
    g = addEdge(g, "1", "2")
    g = addEdge(g, "2", "1")
    g = addEdge(g, "2", "5")
    g = addEdge(g, "3", "0")
    g = addEdge(g, "3", "4")
    g = addEdge(g, "4", "3")
    g = addEdge(g, "4", "5")
    g = addEdge(g, "5", "2")
    g = addEdge(g, "5", "4")

    // DFS from node 0 using stack
    let visited = ""
    let stack = "0"
    let order = ""

    while len(stack) > 0 {
        // Pop from stack (top = last element)
        let n = count(stack)
        let top = split(stack, n - 1)
        if n > 1 {
            let sb = sbNew()
            let i = 0
            while i < n - 1 {
                if i > 0 { sb = sbAppend(sb, ",") }
                sb = sbAppend(sb, split(stack, i))
                i += 1
            }
            stack = sbToString(sb)
        } else {
            stack = ""
        }

        if len(envGet(visited, top)) == 0 {
            visited = envSet(visited, top, "1")
            if len(order) > 0 {
                order = order + "," + top
            } else {
                order = top
            }

            // Push neighbors (reverse order for standard DFS)
            let neighbors = envGet(g, top)
            if len(neighbors) > 0 {
                let nc = count(neighbors)
                let i = nc - 1
                while i >= 0 {
                    let nb = split(neighbors, i)
                    if len(envGet(visited, nb)) == 0 {
                        if len(stack) > 0 {
                            stack = stack + "," + nb
                        } else {
                            stack = nb
                        }
                    }
                    i -= 1
                }
            }
        }
    }

    kp("DFS from node 0: " + order)
}
