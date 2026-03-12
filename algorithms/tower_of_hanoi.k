// Tower of Hanoi

func hanoi(n, from, to, aux) {
    if n == 1 {
        print("Move disk 1 from " + from + " to " + to)
    } else {
        hanoi(n - 1, from, aux, to)
        print("Move disk " + n + " from " + from + " to " + to)
        hanoi(n - 1, aux, to, from)
    }
}

just run {
    let n = 4
    print("Tower of Hanoi with " + n + " disks:")
    print("================================")
    hanoi(n, "A", "C", "B")
}
