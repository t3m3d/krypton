jxt {
    c "stdio.h"
}

struct Point {
    let x
    let y
}

just run {
    let p = Point { x: "10", y: "20" }
    kp(p.x)
}
