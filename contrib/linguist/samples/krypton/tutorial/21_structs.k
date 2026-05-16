// Tutorial 21: Structs
// Named data structures with dot notation

struct Point {
    let x
    let y
}

struct Person {
    let name
    let age
}

func distance(p1, p2) {
    let dx = toInt(p1.x) - toInt(p2.x)
    let dy = toInt(p1.y) - toInt(p2.y)
    emit sqrt(dx * dx + dy * dy) + ""
}

just run {
    // Constructor call
    let p = Point()
    p.x = "3"
    p.y = "4"
    kp("x: " + p.x)
    kp("y: " + p.y)

    // Struct literal
    let q = Point { x: "0", y: "0" }
    kp("distance: " + distance(p, q))

    // Struct in function
    let brian = Person { name: "Brian", age: "30" }
    kp("Hello, " + brian.name)
    kp("Age: " + brian.age)

    // Update a field
    brian.age = "31"
    kp("Next year: " + brian.age)

    // Dynamic struct (no declaration needed)
    let config = structNew()
    setField(config, "debug", "1")
    setField(config, "version", "0.7.2")
    kp("debug: " + getField(config, "debug"))
    kp("version: " + getField(config, "version"))
    kp("fields: " + structFields(config))
}
