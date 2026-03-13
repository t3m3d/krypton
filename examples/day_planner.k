// Day planner - match-based schedule builder
// Demonstrates: match, for-in, const, ternary, compound assignment, range

func dayName(n) {
    let name = ""
    match n {
        1 { name = "Monday" }
        2 { name = "Tuesday" }
        3 { name = "Wednesday" }
        4 { name = "Thursday" }
        5 { name = "Friday" }
        6 { name = "Saturday" }
        7 { name = "Sunday" }
        else { name = "Unknown" }
    }
    emit name
}

func dayType(n) {
    emit n <= 5 ? "Weekday" : "Weekend"
}

func activity(n) {
    let act = ""
    match n {
        1 { act = "Team standup at 9:00" }
        2 { act = "Code review session" }
        3 { act = "Architecture meeting" }
        4 { act = "Sprint planning" }
        5 { act = "Demo and retro" }
        6 { act = "Open source hacking" }
        7 { act = "Rest and recharge" }
        else { act = "Free time" }
    }
    emit act
}

just run {
    const title = "Weekly Planner"
    print(title)
    print(repeat("=", len(title)))
    print("")

    let weekdays = 0
    let weekends = 0

    for day in range(1, 8) {
        const name = dayName(day)
        const typ = dayType(day)
        const act = activity(day)
        const marker = typ == "Weekend" ? "*" : " "

        print(marker + padRight(name, 11, " ") + "[" + typ + "]  " + act)

        if typ == "Weekday" {
            weekdays += 1
        } else {
            weekends += 1
        }
    }

    print("")
    print("Weekdays: " + weekdays + "  Weekend days: " + weekends)
    emit "ok"
}
