// Queue data structure for Krypton
// Queue is a comma-separated string (front is index 0)

go queue {

    // Create new empty queue
    func queueNew() {
        emit ""
    }

    // Enqueue a value at the back
    func enqueue(q, val) {
        if q == "" {
            emit val
        }
        emit q + "," + val
    }

    // Peek at the front value
    func queuePeek(q) {
        emit split(q, 0)
    }

    // Dequeue the front value, returns "value|remainingQueue"
    func dequeue(q) {
        let size = count(q)
        let front = split(q, 0)
        if size <= 1 {
            emit front + "|"
        }
        let sb = sbNew()
        let i = 1
        while i < size {
            if i > 1 {
                sb = sbAppend(sb, ",")
            }
            sb = sbAppend(sb, split(q, i))
            i = i + 1
        }
        emit front + "|" + sbToString(sb)
    }

    // Get queue size
    func queueSize(q) {
        if q == "" {
            emit 0
        }
        emit count(q)
    }

    // Check if queue is empty
    func queueEmpty(q) {
        if q == "" {
            emit 1
        }
        emit 0
    }

    // Print queue elements front to back
    func queuePrint(q) {
        let size = count(q)
        kp("--- Queue (front to back) ---")
        let i = 0
        while i < size {
            kp("  " + split(q, i))
            i = i + 1
        }
        kp("-----------------------------")
    }

    // Get back of queue
    func queueBack(q) {
        let size = count(q)
        emit split(q, size - 1)
    }

    // Check if value is in queue
    func queueContains(q, val) {
        let size = count(q)
        let i = 0
        while i < size {
            if split(q, i) == val {
                emit 1
            }
            i = i + 1
        }
        emit 0
    }
}
