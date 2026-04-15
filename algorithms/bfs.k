// Graph BFS (Breadth-First Search)
// Using adjacency list stored in env

func addEdge(graph, from, to) {
    let neighbors = envGet(graph, from)
    if len(neighbors) == 0 {
        emit envSet(graph, from, to)
    }
    emit envSet(graph, from, neighbors + "," + to)
}

just run {
    // Build a graph
    //   0 -- 1 -- 2
    //   |         |
    //   3 -- 4 -- 5
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

    // BFS from node 0
    let visited = ""
    let queue = "0"
    visited = envSet(visited, "0", "1")
    let order = "0"

    while len(queue) > 0 {
        // Dequeue front
        let front = split(queue, 0)
        let n = count(queue)
        if n > 1 {
            let sb = sbNew()
            let i = 1
            while i < n {
                if i > 1 { sb = sbAppend(sb, ",") }
                sb = sbAppend(sb, split(queue, i))
                i += 1
            }
            queue = sbToString(sb)
        } else {
            queue = ""
        }

        // Visit neighbors
        let neighbors = envGet(g, front)
        if len(neighbors) > 0 {
            let nc = count(neighbors)
            let i = 0
            while i < nc {
                let nb = split(neighbors, i)
                if len(envGet(visited, nb)) == 0 {
                    visited = envSet(visited, nb, "1")
                    if len(queue) > 0 {
                        queue = queue + "," + nb
                    } else {
                        queue = nb
                    }
                    order = order + "," + nb
                }
                i += 1
            }
        }
    }

    kp("BFS from node 0: " + order)
}
