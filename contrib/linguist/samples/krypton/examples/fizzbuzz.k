// FizzBuzz - classic programming challenge

just run {
    let i = 1
    while i <= 100 {
        if i % 15 == 0 {
            kp("FizzBuzz")
        } else if i % 3 == 0 {
            kp("Fizz")
        } else if i % 5 == 0 {
            kp("Buzz")
        } else {
            kp(i)
        }
        i += 1
    }
}
