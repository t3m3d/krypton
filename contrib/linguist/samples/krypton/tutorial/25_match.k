// Tutorial 25: Match Statements
// Pattern matching on string values

func dayType(day) {
    match day {
        "Sat" { emit "weekend" }
        "Sun" { emit "weekend" }
        "Mon" { emit "weekday" }
        "Tue" { emit "weekday" }
        "Wed" { emit "weekday" }
        "Thu" { emit "weekday" }
        "Fri" { emit "weekday" }
        else  { emit "unknown" }
    }
}

func httpStatus(code) {
    match code {
        "200" { emit "OK" }
        "201" { emit "Created" }
        "400" { emit "Bad Request" }
        "401" { emit "Unauthorized" }
        "403" { emit "Forbidden" }
        "404" { emit "Not Found" }
        "500" { emit "Internal Server Error" }
        else  { emit "Unknown Status" }
    }
}

just run {
    // Basic match
    let color = "blue"
    match color {
        "red"   { kp("warm color") }
        "blue"  { kp("cool color") }
        "green" { kp("nature color") }
        else    { kp("other color") }
    }

    // Match in function
    let days = "Mon,Wed,Fri,Sat,Sun"
    for day in days {
        kp(day + ": " + dayType(day))
    }

    // Match on computed value
    let codes = "200,404,500,201"
    for code in codes {
        kp(code + " " + httpStatus(code))
    }

    // Match with variable capture (using else)
    let val = "42"
    let label = ""
    match val {
        "0"  { label = "zero" }
        "1"  { label = "one" }
        else { label = "other: " + val }
    }
    kp(label)
}
