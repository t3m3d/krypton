// Tower of Hanoi

func hanoi(n, from, to, aux) {
    if n == 1 {
        kp("Move disk 1 from " + from + " to " + to)
    } else {
        hanoi(n - 1, from, aux, to)
        kp("Move disk " + n + " from " + from + " to " + to)
        hanoi(n - 1, aux, to, from)
    }
}

just run {
    let n = 4
    kp("Tower of Hanoi with " + n + " disks:")
    kp("================================")
    hanoi(n, "A", "C", "B")
}
